!@descr: table-driven two-device checks of the reductions, scans, softmax and extremum positions
! Each function runs on seeded (5, 4, 3) arrays, a batch of them along a fourth dimension, in every form (one
! dimension, a list, all of them) against a plain Fortran real64 oracle applied to the elements it reduces, taken
! in array element order: float32 on every device, float64 on the CPU. Float results are judged by the frozen
! tolerances of mlxf_test_defs (an error relative to max(1, |reference|)); extrema, logical reductions, counts
! and positions are exact.
module mlxf_ops_reduce_tester
use, intrinsic :: iso_fortran_env, only: int8, int16, int32, int64, real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_value, ieee_quiet_nan, ieee_is_finite, ieee_positive_inf
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                            MLX_DTYPES, mlx_astype, mlx_zeros, reshape, sum, product, maxval, minval, all, any, count, &
                            mlx_mean, mlx_median, mlx_var, mlx_std, mlx_logsumexp, maxloc, minloc, mlx_cumsum, abs, &
                            mlx_cumprod, mlx_cummax, mlx_cummin, mlx_logcumsumexp, mlx_softmax, cmplx
use mlxf_test_utils,  only: assert_true, assert_int, test_devices, device_name, set_fixed_seed
use mlxf_test_defs,   only: ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED, ELEM_CEILING, REDUCE_TOLERANCES, REDUCE_NBATCH, &
                            elem_tolerance
use mlxf_test_reduce, only: nan_maxval, nan_max
implicit none
private
public :: run_all_ops_reduce_tests

! the fixture's extents; a form with dimensions runs on a batch of fixtures along dimension 4
integer, parameter :: N1 = 5, N2 = 4, N3 = 3, NB = REDUCE_NBATCH
! the forms of a reduction: every dimension, one dimension, a list of dimensions
integer, parameter :: FORM_ALL = 0, FORM_DIM = 1, FORM_DIMS = 2

! how a wrapper is called: the dimensions it takes (n of dims), keepdims, a scan's direction and inclusion, and
! whether the function maps every element (a scan, a softmax) instead of reducing them to one
type :: reduce_form
    integer :: mode = FORM_ALL
    integer :: dims(3) = 0
    integer :: n = 0
    logical :: keepdims = .false.
    logical :: reverse = .false., inclusive = .true.
    logical :: maps = .false.
end type reduce_form

abstract interface
    function array_reduce( a, form ) result(r)
        import :: mlx_array, reduce_form
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
    end function array_reduce

    ! the oracle of the elements x a function takes together: one value, or one per element for a scan
    subroutine block_oracle( x, y )
        import :: real64
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
    end subroutine block_oracle
end interface

! a reduction or a scan, its oracle and its input domain [lo, hi] (whole numbers when integral); exact results
! are equal to the oracle's
type :: reduce_case
    character(len=24)                        :: name = ''
    procedure(array_reduce), pointer, nopass :: f      => null()
    procedure(block_oracle), pointer, nopass :: oracle => null()
    real(real64)                             :: lo = 0._real64, hi = 0._real64
    logical                                  :: integral = .false., exact = .false.
end type reduce_case

! what the forms of one function gave: the largest error, and whether every result had its expected shape
type :: form_result
    real(real64) :: err    = 0._real64
    logical      :: shaped = .true.
end type form_result

contains

    subroutine run_all_ops_reduce_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all ops_reduce tests ****'
        call assert_true(all(REDUCE_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance of a reduction is within the ceiling of 64 float32 epsilons')
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_reduce_family
            call test_scan_family
            call test_softmax
            call test_positions
            call test_reduce_conventions
            call test_integer_statistics
            call test_mean_range
            call test_half_statistics
            call test_empty_extrema
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_ops_reduce_tests

    ! the seeds every family runs: the calibration seed, then the judged ones
    function family_seeds() result(seeds)
        integer, allocatable :: seeds(:)
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
    end function family_seeds

    ! the frozen tolerances of a function (zero, failing every inexact check, when it has none)
    function tolerance_of( name ) result(t)
        character(len=*), intent(in) :: name
        type(elem_tolerance) :: t
        integer              :: k
        t = elem_tolerance(name, 0._real64, 0._real64)
        do k = 1, size(REDUCE_TOLERANCES)
            if( trim(REDUCE_TOLERANCES(k)%name) == trim(name) ) t = REDUCE_TOLERANCES(k)
        end do
    end function tolerance_of

    ! the fixture from a fixed seed, in [lo, hi], rounded once to float32 (whole numbers when integral)
    subroutine draw( x, lo, hi, seed, integral )
        real(real64), intent(out) :: x(:,:,:,:)
        real(real64), intent(in)  :: lo, hi
        integer,      intent(in)  :: seed
        logical,      intent(in)  :: integral
        real(real64) :: u(size(x, 1), size(x, 2), size(x, 3), size(x, 4))
        call set_fixed_seed(seed)
        call random_number(u)
        x = lo+(hi-lo)*u
        if( integral ) x = anint(x)
        x = real(real(x, real32), real64)
    end subroutine draw

    ! the forms every reduction runs: all, each dimension, each pair, the three, and two with keepdims
    subroutine reduce_forms( forms )
        type(reduce_form), allocatable, intent(out) :: forms(:)
        allocate(forms(10))
        forms(1) = reduce_form(FORM_ALL, [0, 0, 0], 0)
        forms(2) = reduce_form(FORM_DIM, [1, 0, 0], 1)
        forms(3) = reduce_form(FORM_DIM, [2, 0, 0], 1)
        forms(4) = reduce_form(FORM_DIM, [3, 0, 0], 1)
        forms(5) = reduce_form(FORM_DIMS, [1, 2, 0], 2)
        forms(6) = reduce_form(FORM_DIMS, [3, 1, 0], 2)
        forms(7) = reduce_form(FORM_DIMS, [2, 3, 0], 2)
        forms(8) = reduce_form(FORM_DIMS, [1, 2, 3], 3)
        forms(9) = reduce_form(FORM_DIM, [2, 0, 0], 1, keepdims=.true.)
        forms(10) = reduce_form(FORM_DIMS, [1, 3, 0], 2, keepdims=.true.)
    end subroutine reduce_forms

    ! which dimensions a form takes together
    function taken( form ) result(mask)
        type(reduce_form), intent(in) :: form
        logical :: mask(3)
        integer :: i
        mask = form%mode == FORM_ALL
        do i = 1, form%n
            mask(form%dims(i)) = .true.
        end do
    end function taken

    ! the oracle applied to every block of the dimensions the form takes together, in array element order: one
    ! value per block in the order of the kept dimensions, or (a map) one per element. A reversed scan runs on the
    ! reversed block; an exclusive one gives each element its predecessor's value and none, NaN, to the first
    subroutine reference( x, form, oracle, ref )
        real(real64),      intent(in)               :: x(:,:,:)
        type(reduce_form), intent(in)               :: form
        procedure(block_oracle)                     :: oracle
        real(real64),      allocatable, intent(out) :: ref(:)
        real(real64), allocatable :: full(:,:,:), block(:), out(:)
        logical                   :: mask(3)
        integer                   :: n(3), lo(3), hi(3), e(3), i1, i2, i3, m
        mask = taken(form)
        n = shape(x)
        e = merge(1, n, mask)
        allocate(full(n(1), n(2), n(3)))
        do i3 = 1, e(3)
            do i2 = 1, e(2)
                do i1 = 1, e(1)
                    lo = [i1, i2, i3]
                    hi = merge(n, lo, mask)
                    block = reshape(x(lo(1):hi(1), lo(2):hi(2), lo(3):hi(3)), [product(hi-lo+1)])
                    m = size(block)
                    if( .not. form%maps )then
                        allocate(out(1))
                        call oracle(block, out)
                        full(i1, i2, i3) = out(1)
                    else
                        allocate(out(m))
                        if( form%reverse ) block = block(m:1:-1)
                        call oracle(block, out)
                        if( .not. form%inclusive )then
                            out(2:m) = out(1:m-1)
                            out(1) = ieee_value(1._real64, ieee_quiet_nan)
                        endif
                        if( form%reverse ) out = out(m:1:-1)
                        full(lo(1):hi(1), lo(2):hi(2), lo(3):hi(3)) = reshape(out, hi-lo+1)
                    endif
                    deallocate(out)
                end do
            end do
        end do
        if( form%maps )then
            ref = reshape(full, [size(full)])
        else
            ref = reshape(full(1:e(1), 1:e(2), 1:e(3)), [product(e)])
        endif
    end subroutine reference

    ! the reference of a form with dimensions on the batch: every fixture's, following each other along the
    ! batch dimension
    subroutine batch_reference( x, form, oracle, ref )
        real(real64),      intent(in)               :: x(:,:,:,:)
        type(reduce_form), intent(in)               :: form
        procedure(block_oracle)                     :: oracle
        real(real64),      allocatable, intent(out) :: ref(:)
        real(real64), allocatable :: one(:)
        integer                   :: b, m
        do b = 1, size(x, 4)
            call reference(x(:, :, :, b), form, oracle, one)
            m = size(one)
            if( b == 1 ) allocate(ref(m*size(x, 4)))
            ref((b-1)*m+1:b*m) = one
        end do
    end subroutine batch_reference

    ! the arrays a wrapper runs on, in one kind: the batch, then each fixture alone for the whole-array form
    subroutine operands( x, as_float64, arrays )
        real(real64),    intent(in)               :: x(:,:,:,:)
        logical,         intent(in)               :: as_float64
        type(mlx_array), allocatable, intent(out) :: arrays(:)
        integer :: b
        allocate(arrays(size(x, 4)+1))
        if( as_float64 )then
            arrays(1) = mlx_from(x)
        else
            arrays(1) = mlx_from(real(x, real32))
        endif
        do b = 1, size(x, 4)
            if( as_float64 )then
                arrays(b+1) = mlx_from(x(:, :, :, b))
            else
                arrays(b+1) = mlx_from(real(x(:, :, :, b), real32))
            endif
        end do
    end subroutine operands

    ! the values of r in array element order as real64, whatever its kind
    subroutine values_of( r, y )
        type(mlx_array), intent(in)               :: r
        real(real64),    allocatable, intent(out) :: y(:)
        type(mlx_array)           :: flat, f32
        real(real32), allocatable :: y32(:)
        integer                   :: n
        n = int(r%size())
        allocate(y(n))
        flat = reshape(r, [n])
        if( r%kind() == MLX_DTYPES%float64 )then
            call mlx_to(y, flat)
        else
            allocate(y32(n))
            f32 = mlx_astype(flat, MLX_DTYPES%float32)
            call mlx_to(y32, f32)
            y = real(y32, real64)
        endif
    end subroutine values_of

    ! the largest error of r relative to max(1, |ref|) where ref has a value; a wrong size or a NaN is huge
    function rel_error( r, ref ) result(err)
        type(mlx_array), intent(in) :: r
        real(real64),    intent(in) :: ref(:)
        real(real64)              :: err
        real(real64), allocatable :: y(:)
        logical,      allocatable :: judged(:)
        call values_of(r, y)
        err = huge(1._real64)
        if( size(y) /= size(ref) ) return
        judged = .not. ieee_is_nan(ref)
        if( any(judged .and. ieee_is_nan(y)) ) return
        err = nan_maxval(pack(abs(y-ref)/max(1._real64, abs(ref)), judged))
    end function rel_error

    ! the shape a form's result must have: of a map, its operand's (rank 1 for the whole array); of a
    ! reduction, the kept dimensions; then the batch, for a form with dimensions
    function expected_shape( form ) result(s)
        type(reduce_form), intent(in) :: form
        integer, allocatable :: s(:)
        logical              :: mask(3)
        mask = taken(form)
        if( form%maps )then
            s = [N1, N2, N3]
            if( form%mode == FORM_ALL ) s = [N1*N2*N3]
        else if( form%keepdims )then
            s = merge(1, [N1, N2, N3], mask)
        else
            s = pack([N1, N2, N3], .not. mask)
        endif
        if( form%mode /= FORM_ALL ) s = [s, NB]
    end function expected_shape

    ! whether a has exactly the shape want
    logical function has_shape( a, want )
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: want(:)
        integer, allocatable :: got(:)
        got = a%shape()
        has_shape = size(got) == size(want)
        if( has_shape ) has_shape = all(got == want)
    end function has_shape

    ! one measured error against its tolerance, printed in float32 epsilons for the calibration record
    subroutine judge( err, tol, label, dtype, seed )
        real(real64),     intent(in) :: err, tol
        character(len=*), intent(in) :: label, dtype
        integer,          intent(in) :: seed
        character(len=160) :: line
        write(line,'(A,I0,A,ES16.9,A,F8.3,A)') '    error '//trim(label)//' '//device_name(mlx_default_device())// &
            &' '//dtype//' seed=', seed, ': ', err, ' (', err/real(epsilon(1._real32), real64), ' eps32)'
        write(*,'(A)') trim(line)
        call assert_true(err <= tol, trim(label)//' '//dtype//' within its frozen tolerance on the '// &
            &device_name(mlx_default_device()))
    end subroutine judge

    ! one form of a function in the kind of a: a form with dimensions runs once on the batch, the whole-array
    ! form on every fixture
    subroutine form_error( c, x, a, form, res )
        type(reduce_case), intent(in)    :: c
        real(real64),      intent(in)    :: x(:,:,:,:)
        type(mlx_array),   intent(in)    :: a(:)
        type(reduce_form), intent(in)    :: form
        type(form_result), intent(inout) :: res
        type(mlx_array)           :: r
        real(real64), allocatable :: ref(:)
        integer                   :: b
        if( form%mode /= FORM_ALL )then
            call batch_reference(x, form, c%oracle, ref)
            r = c%f(a(1), form)
            if( .not. has_shape(r, expected_shape(form)) ) res%shaped = .false.
            res%err = max(res%err, rel_error(r, ref))
            return
        endif
        do b = 1, size(x, 4)
            call reference(x(:, :, :, b), form, c%oracle, ref)
            r = c%f(a(b+1), form)
            if( .not. has_shape(r, expected_shape(form)) ) res%shaped = .false.
            res%err = max(res%err, rel_error(r, ref))
        end do
    end subroutine form_error

    ! a function over its forms in one kind: the error judged, the shapes asserted
    subroutine run_case( c, x, as_float64, forms, seed )
        type(reduce_case), intent(in) :: c
        real(real64),      intent(in) :: x(:,:,:,:)
        logical,           intent(in) :: as_float64
        type(reduce_form), intent(in) :: forms(:)
        integer,           intent(in) :: seed
        type(mlx_array), allocatable :: a(:)
        type(elem_tolerance)         :: tol
        type(form_result)            :: res
        integer                      :: k
        tol = tolerance_of(c%name)
        if( c%exact ) tol = elem_tolerance(c%name, 0._real64, 0._real64)
        call operands(x, as_float64, a)
        do k = 1, size(forms)
            call form_error(c, x, a, forms(k), res)
        end do
        if( as_float64 )then
            call judge(res%err, tol%f64, c%name, 'float64', seed)
        else
            call judge(res%err, tol%f32, c%name, 'float32', seed)
        endif
        call assert_true(res%shaped, trim(c%name)//': every form has its shape, the kept dimensions in order')
    end subroutine run_case

    ! every reduction against its oracle on each seed, over all forms: float32, and float64 on the CPU
    subroutine test_reduce_family
        type(reduce_case)              :: cases(12)
        type(reduce_form), allocatable :: forms(:)
        integer,           allocatable :: seeds(:)
        real(real64)                   :: x(N1, N2, N3, NB)
        integer                        :: c, k
        write(*,'(a)') 'test_reduce_family'
        cases(1) = reduce_case('sum', r_sum, o_sum, -2._real64, 2._real64, .false., .false.)
        cases(2) = reduce_case('product', r_product, o_product, 0.5_real64, 1.5_real64, .false., .false.)
        cases(3) = reduce_case('maxval', r_maxval, o_maxval, -2._real64, 2._real64, .false., .true.)
        cases(4) = reduce_case('minval', r_minval, o_minval, -2._real64, 2._real64, .false., .true.)
        cases(5) = reduce_case('all', r_all, o_all, 0._real64, 2._real64, .true., .true.)
        cases(6) = reduce_case('any', r_any, o_any, 0._real64, 2._real64, .true., .true.)
        cases(7) = reduce_case('count', r_count, o_count, 0._real64, 2._real64, .true., .true.)
        cases(8) = reduce_case('mlx_mean', r_mean, o_mean, -2._real64, 2._real64, .false., .false.)
        cases(9) = reduce_case('mlx_median', r_median, o_median, -2._real64, 2._real64, .false., .false.)
        cases(10) = reduce_case('mlx_var', r_var, o_var, -2._real64, 2._real64, .false., .false.)
        cases(11) = reduce_case('mlx_std', r_std, o_std, -2._real64, 2._real64, .false., .false.)
        cases(12) = reduce_case('mlx_logsumexp', r_logsumexp, o_logsumexp, -3._real64, 3._real64, .false., .false.)
        call reduce_forms(forms)
        seeds = family_seeds()
        do k = 1, size(seeds)
            do c = 1, size(cases)
                call draw(x, cases(c)%lo, cases(c)%hi, 2000*seeds(k)+c, cases(c)%integral)
                call run_case(cases(c), x, .false., forms, seeds(k))
                if( mlx_default_device() == MLX_DEVICES%cpu ) call run_case(cases(c), x, .true., forms, seeds(k))
            end do
        end do
    end subroutine test_reduce_family

    ! mean, variance and standard deviation of integer and boolean arrays: the input is converted to float32 before
    ! the arithmetic, so a large total cannot wrap. Exact fixtures (values and partial sums exact in float32) within
    ! one float32 epsilon of max(1, |answer|), every integer kind; general integer fixtures in [-2e9, 2e9] judged by the
    ! frozen tolerances of the float32 family on the same data scaled by 1e-9 (the family's domain [-2, 2])
    subroutine test_integer_statistics
        integer,           parameter   :: KINDS(9) = [MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, &
            &MLX_DTYPES%int64, MLX_DTYPES%uint8, MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64, MLX_DTYPES%bool]
        real(real64),      parameter   :: SCALE = 1.e9_real64
        type(mlx_array)                :: a, p, r
        type(mlx_array),   allocatable :: ops(:)
        type(reduce_case)              :: cases(3)
        type(reduce_form), allocatable :: forms(:)
        type(form_result)              :: res
        type(elem_tolerance)           :: tol
        integer(int32),    allocatable :: img(:,:)
        integer,           allocatable :: seeds(:)
        real(real64),      allocatable :: ref(:), y(:)
        real(real64)                   :: x(N1, N2, N3, NB), value
        integer                        :: k, c, j, b, w
        write(*,'(a)') 'test_integer_statistics'
        allocate(img(1024, 1024), source=4096_int32)
        a = mlx_from(img)
        call exact(mlx_mean(a), 4096._real64, 'the mean of a 1024 x 1024 int32 image of 4096')
        call exact(mlx_mean(a, 1), 4096._real64, 'its mean along dimension 1')
        call exact(mlx_mean(a, [1, 2], keepdims=.true.), 4096._real64, 'its mean over both dimensions, kept')
        call exact(mlx_var(a), 0._real64, 'its variance')
        call exact(mlx_var(a, 2, ddof=1), 0._real64, 'its variance along dimension 2 with ddof 1')
        call exact(mlx_std(a), 0._real64, 'its standard deviation')
        call exact(mlx_std(a, [2, 1]), 0._real64, 'its standard deviation over both dimensions')
        p = mlx_from([2000000000_int32, 2000000000_int32])
        call exact(mlx_mean(p), 2.e9_real64, 'the mean of two int32 values 2000000000')
        call exact(mlx_mean(p, 1, keepdims=.true.), 2.e9_real64, 'along dimension 1, kept')
        call exact(mlx_var(p), 0._real64, 'their variance')
        call exact(mlx_var(p, ddof=1), 0._real64, 'their variance with ddof 1')
        call exact(mlx_std(p, 1), 0._real64, 'their standard deviation')
        p = mlx_from([2000000000_int32, -2000000000_int32, 2000000000_int32, -2000000000_int32])
        call exact(mlx_mean(p), 0._real64, 'the mean of [2e9, -2e9, 2e9, -2e9]')
        call exact(mlx_var(p), 4.e18_real64, 'their variance, 4e18')
        call exact(mlx_std(p), 2.e9_real64, 'their standard deviation, 2e9')
        p = mlx_from([2000000000_int32, -2000000000_int32])
        call exact(mlx_var(p, ddof=1), 8.e18_real64, 'the variance of [2e9, -2e9] with ddof 1, 8e18')
        call exact(mlx_std(p, 1, ddof=1), sqrt(8.e18_real64), 'its standard deviation with ddof 1')
        ! a constant of every integer kind and of booleans, at a value exact in float32 and the kind
        do k = 1, size(KINDS)
            select case( k )
                case( 1 )
                    p = mlx_from(spread(100_int8, 1, 4096))
                    value = 100._real64
                case( 2 )
                    p = mlx_from(spread(30000_int16, 1, 4096))
                    value = 30000._real64
                case( 3 )
                    p = mlx_from(spread(2000000000_int32, 1, 8))
                    value = 2.e9_real64
                case( 4 )
                    p = mlx_from(spread(4611686018427387904_int64, 1, 2))
                    value = 4611686018427387904._real64
                case( 5 )
                    p = mlx_astype(mlx_from(spread(200_int32, 1, 4096)), KINDS(k))
                    value = 200._real64
                case( 6 )
                    p = mlx_astype(mlx_from(spread(60000_int32, 1, 4096)), KINDS(k))
                    value = 60000._real64
                case( 7 )
                    p = mlx_astype(mlx_from(spread(4000000000_int64, 1, 2)), KINDS(k))
                    value = 4.e9_real64
                case( 8 )
                    ! -2**63 as int64 has the bits of 2**63 as uint64
                    p = mlx_astype(mlx_from(spread(-huge(1_int64)-1_int64, 1, 2)), KINDS(k))
                    value = 9223372036854775808._real64
                case default
                    p = mlx_from(spread(1_int32, 1, 4096)) > 0._real32
                    value = 1._real64
            end select
            call assert_int(KINDS(k), p%kind(), 'the constant fixture has the kind under test')
            r = mlx_mean(p)
            call assert_int(MLX_DTYPES%float32, r%kind(), 'the mean of an integer or boolean array is float32')
            call exact(r, value, 'the mean of a constant of that kind')
            call exact(mlx_mean(p, 1), value, 'along dimension 1')
            call exact(mlx_var(p), 0._real64, 'its variance')
            call exact(mlx_std(p, 1), 0._real64, 'its standard deviation along dimension 1')
        end do
        ! general integer fixtures, int32 and int64, against the family's oracle and frozen tolerances
        cases(1) = reduce_case('mlx_mean', r_mean, o_mean, -2._real64, 2._real64, .false., .false.)
        cases(2) = reduce_case('mlx_var', r_var, o_var, -2._real64, 2._real64, .false., .false.)
        cases(3) = reduce_case('mlx_std', r_std, o_std, -2._real64, 2._real64, .false., .false.)
        call reduce_forms(forms)
        seeds = family_seeds()
        do k = 1, size(seeds)
            do c = 1, size(cases)
                call draw(x, -2.e9_real64, 2.e9_real64, 2000*seeds(k)+300+c, .true.)
                tol = tolerance_of(cases(c)%name)
                do w = 1, 2
                    allocate(ops(NB+1))
                    if( w == 1 )then
                        ops(1) = mlx_from(int(x, int32))
                    else
                        ops(1) = mlx_from(int(x, int64))
                    endif
                    do b = 1, NB
                        if( w == 1 )then
                            ops(b+1) = mlx_from(int(x(:, :, :, b), int32))
                        else
                            ops(b+1) = mlx_from(int(x(:, :, :, b), int64))
                        endif
                    end do
                    res = form_result()
                    do j = 1, size(forms)
                        if( forms(j)%mode /= FORM_ALL )then
                            call batch_reference(x, forms(j), cases(c)%oracle, ref)
                            r = cases(c)%f(ops(1), forms(j))
                            call scaled_error(r, ref, merge(SCALE**2, SCALE, c == 2), res%err)
                        else
                            do b = 1, NB
                                call reference(x(:, :, :, b), forms(j), cases(c)%oracle, ref)
                                r = cases(c)%f(ops(b+1), forms(j))
                                call scaled_error(r, ref, merge(SCALE**2, SCALE, c == 2), res%err)
                            end do
                        endif
                    end do
                    call judge(res%err, tol%f32, cases(c)%name, merge('int32', 'int64', w == 1), seeds(k))
                    deallocate(ops)
                end do
            end do
        end do
    contains
        ! a result of one element (any rank) within one float32 epsilon of max(1, |want|)
        subroutine exact( res, want, label )
            type(mlx_array),  intent(in) :: res
            real(real64),     intent(in) :: want
            character(len=*), intent(in) :: label
            call values_of(res, y)
            call assert_true(size(y) > 0 .and. all(abs(y-want) <= real(epsilon(1._real32), real64)*max(1._real64, &
                &abs(want))), label//' is exact (within one float32 epsilon)')
        end subroutine exact

    end subroutine test_integer_statistics

    ! the mean of floating values near the ends of the range, against the bounds frozen before the change: two equal
    ! values within 8 epsilons of the kind (float32 2e38 on every device, float64 1e308 on the CPU), every form; a
    ! fixture of mixed magnitudes and signs within (n+2) epsilons of the mean of the magnitudes; complex parts near
    ! the top of the range; zeros, NaN and infinities as IEEE arithmetic gives them; an empty mean NaN, not refused
    subroutine test_mean_range
        integer,      parameter   :: NMIX = 1024
        type(mlx_array)           :: a, r
        real(real64), allocatable :: y(:)
        real(real32)              :: x(NMIX), u(NMIX), big(4, 3)
        complex(real32)           :: z(1)
        real(real64)              :: want, eps
        write(*,'(a)') 'test_mean_range'
        eps = real(epsilon(1._real32), real64)
        a = mlx_from([2.e38_real32, 2.e38_real32])
        want = real(2.e38_real32, real64)
        call near(mlx_mean(a), want, 8._real64*eps*want, 'the mean of two float32 values 2e38')
        call near(mlx_mean(a, 1), want, 8._real64*eps*want, 'along dimension 1')
        call near(mlx_mean(a, keepdims=.true.), want, 8._real64*eps*want, 'kept')
        big = 2.e38_real32
        a = mlx_from(big)
        call near(mlx_mean(a, 1), want, 8._real64*eps*want, 'a (4, 3) array of 2e38 along dimension 1')
        call near(mlx_mean(a, [1, 2]), want, 8._real64*eps*want, 'over both dimensions')
        call near(mlx_mean(a, [2], keepdims=.true.), want, 8._real64*eps*want, 'over dimension 2, kept')
        if( mlx_default_device() == MLX_DEVICES%cpu )then
            call near(mlx_mean(mlx_from([1.e308_real64, 1.e308_real64])), 1.e308_real64, &
                &8._real64*epsilon(1._real64)*1.e308_real64, 'the mean of two float64 values 1e308')
        endif
        ! mixed magnitudes from 1e-30 to 1e37, random signs: a partial sum may pass 3e38 in any order
        call set_fixed_seed(ELEM_SEED_CALIBRATION)
        call random_number(u)
        x = real(10._real64**(-30._real64+67._real64*real(u, real64)), real32)
        call random_number(u)
        x = merge(x, -x, u > 0.5_real32)
        x(1:8) = 3.e38_real32
        want = sum(real(x, real64))/NMIX
        call near(mlx_mean(mlx_from(x)), want, real(NMIX+2, real64)*eps*sum(abs(real(x, real64)))/NMIX, &
            &'the mean of 1024 values of mixed magnitudes and signs, eight of them 3e38')
        call near(mlx_mean(mlx_from([3.e38_real32, -3.e38_real32, 1._real32])), 1._real64/3._real64, &
            &5._real64*eps*2.e38_real64, 'signed cancellation [3e38, -3e38, 1]')
        call near(mlx_mean(mlx_from([0._real32, 0._real32])), 0._real64, 0._real64, 'the mean of zeros is 0')
        z = cmplx(2.e38_real32, -2.e38_real32, real32)
        r = mlx_mean(mlx_from([z(1), z(1)]))
        call mlx_to(z, reshape(r, [1]))
        call assert_true(abs(real(z(1), real64)-2.e38_real64) <= 8._real64*eps*2.e38_real64 .and. &
            &abs(real(aimag(z(1)), real64)+2.e38_real64) <= 8._real64*eps*2.e38_real64, &
            &'the mean of two complex values (2e38, -2e38) keeps both parts')
        call values_of(mlx_mean(mlx_from([ieee_value(1._real32, ieee_quiet_nan), 1._real32])), y)
        call assert_true(ieee_is_nan(y(1)), 'a NaN makes the mean NaN')
        call values_of(mlx_mean(mlx_from([ieee_value(1._real32, ieee_positive_inf), 1._real32])), y)
        call assert_true(.not. ieee_is_finite(y(1)) .and. y(1) > 0._real64, 'an infinity makes it +infinity')
        call values_of(mlx_mean(mlx_from([ieee_value(1._real32, ieee_positive_inf), &
            &-ieee_value(1._real32, ieee_positive_inf)])), y)
        call assert_true(ieee_is_nan(y(1)), 'opposite infinities make it NaN')
        r = mlx_mean(mlx_zeros([0, 3]), 1)
        call values_of(r, y)
        call assert_true(all(r%shape() == [3]) .and. all(ieee_is_nan(y)), &
            &'the mean over an extent of zero is NaN, in the reduction''s shape, not a refusal')
    contains
        subroutine near( res, ref, tol, label )
            type(mlx_array),  intent(in) :: res
            real(real64),     intent(in) :: ref, tol
            character(len=*), intent(in) :: label
            real(real64), allocatable :: v(:)
            call values_of(res, v)
            call assert_true(size(v) > 0 .and. all(ieee_is_finite(v)) .and. all(abs(v-ref) <= tol), &
                &label//' is within its bound')
        end subroutine near

    end subroutine test_mean_range

    ! mlx_mean, mlx_var and mlx_std of 65,536 float16 and bfloat16 values, whose answers the kind holds but whose sums
    ! it does not (float16 overflows at 65504, bfloat16 stops adding ones at 256): ones (1, 0, 0) and alternating 1
    ! and 3 (2, 1, 1), every answer exact, over every element, along dimension 1 of a (65536, 1) array, over the list
    ! [1, 2] of a (32768, 2) array, and kept; the result in the operand's kind
    subroutine test_half_statistics
        integer, parameter        :: NH = 65536
        real(real32)              :: x(NH)
        type(mlx_array)           :: a, a1, a2
        integer                   :: i, k, j, dt
        character(len=8)          :: label
        character(len=5)          :: what
        write(*,'(a)') 'test_half_statistics'
        do k = 1, 2
            dt    = merge(MLX_DTYPES%float16, MLX_DTYPES%bfloat16, k == 1)
            label = merge('float16 ', 'bfloat16', k == 1)
            do j = 1, 2
                if( j == 1 )then
                    x = 1._real32
                    what = 'ones'
                else
                    do i = 1, NH
                        x(i) = merge(1._real32, 3._real32, mod(i, 2) == 1)
                    end do
                    what = '1 3'
                endif
                a  = mlx_astype(mlx_from(x), dt)
                a1 = reshape(a, [NH, 1])
                a2 = reshape(a, [NH/2, 2])
                call check(mlx_mean(a), merge(1._real64, 2._real64, j == 1), 'mlx_mean')
                call check(mlx_mean(a1, 1), merge(1._real64, 2._real64, j == 1), 'mlx_mean along dimension 1')
                call check(mlx_mean(a2, [1, 2]), merge(1._real64, 2._real64, j == 1), 'mlx_mean over [1, 2]')
                call check(mlx_mean(a, keepdims=.true.), merge(1._real64, 2._real64, j == 1), 'mlx_mean kept')
                call check(mlx_var(a), merge(0._real64, 1._real64, j == 1), 'mlx_var')
                call check(mlx_var(a1, 1), merge(0._real64, 1._real64, j == 1), 'mlx_var along dimension 1')
                call check(mlx_var(a2, [1, 2]), merge(0._real64, 1._real64, j == 1), 'mlx_var over [1, 2]')
                call check(mlx_std(a), merge(0._real64, 1._real64, j == 1), 'mlx_std')
                call check(mlx_std(a2, [1, 2]), merge(0._real64, 1._real64, j == 1), 'mlx_std over [1, 2]')
            end do
        end do
    contains
        subroutine check( res, want, name )
            type(mlx_array),  intent(in) :: res
            real(real64),     intent(in) :: want
            character(len=*), intent(in) :: name
            real(real64), allocatable :: v(:)
            call values_of(res, v)
            call assert_int(dt, res%kind(), trim(label)//' '//trim(what)//': '//name//' is in the operand''s kind')
            call assert_true(size(v) == 1 .and. all(abs(v-want) <= 0._real64), &
                &trim(label)//' '//trim(what)//': '//name//' of 65536 values is the exact answer')
        end subroutine check

    end subroutine test_half_statistics

    ! maxval and minval over an extent of zero give Fortran's identities in the operand's kind and the reduction's
    ! shape (-huge and huge for reals, -huge-1 and huge for integers, 0 and the largest value for the unsigned
    ! kinds, the largest finite half values, false and true), in every form; a reduction over nonzero extents of
    ! an empty array keeps MLX's (empty) result
    subroutine test_empty_extrema
        integer, parameter :: KINDS(13) = [MLX_DTYPES%float32, MLX_DTYPES%float64, MLX_DTYPES%float16, &
            &MLX_DTYPES%bfloat16, MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, MLX_DTYPES%uint8, &
            &MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64, MLX_DTYPES%bool]
        type(mlx_array)           :: a, r
        real(real64), allocatable :: y(:)
        real(real64)              :: lo, hi
        integer                   :: k
        logical                   :: shaped, exact
        write(*,'(a)') 'test_empty_extrema'
        do k = 1, size(KINDS)
            if( mlx_default_device() /= MLX_DEVICES%cpu .and. KINDS(k) == MLX_DTYPES%float64 ) cycle
            select case( k )
                case( 1 )
                    lo = -huge(1._real32)
                case( 2 )
                    lo = -huge(1._real64)
                case( 3 )
                    lo = -65504._real64
                case( 4 )
                    lo = -3.38953139e38_real64
                case( 5 )
                    lo = -128._real64
                case( 6 )
                    lo = -32768._real64
                case( 7 )
                    lo = -2147483648._real64
                case( 8 )
                    lo = -9223372036854775808._real64
                case default
                    lo = 0._real64
            end select
            select case( k )
                case( 5:8 )
                    hi = -lo-1._real64
                case( 9 )
                    hi = 255._real64
                case( 10 )
                    hi = 65535._real64
                case( 11 )
                    hi = 4294967295._real64
                case( 12 )
                    hi = 18446744073709551615._real64
                case( 13 )
                    hi = 1._real64
                case default
                    hi = -lo
            end select
            a = mlx_zeros([0, 3], KINDS(k))
            r = maxval(a, 1)
            shaped = has_shape(r, [3])
            exact = holds(r, lo, KINDS(k), .true.)
            call assert_true(r%kind() == KINDS(k) .and. shaped .and. exact, &
                &'maxval of an empty dimension: the most negative value of the kind, three of them')
            r = minval(a, 1)
            shaped = has_shape(r, [3])
            exact = holds(r, hi, KINDS(k), .false.)
            call assert_true(r%kind() == KINDS(k) .and. shaped .and. exact, &
                &'minval of an empty dimension: the largest value of the kind')
            r = maxval(a)
            shaped = has_shape(r, [integer ::])
            exact = holds(r, lo, KINDS(k), .true.)
            call assert_true(shaped .and. exact, 'maxval of the whole empty array: rank 0, the same')
            r = minval(a, keepdims=.true.)
            shaped = has_shape(r, [1, 1])
            exact = holds(r, hi, KINDS(k), .false.)
            call assert_true(r%kind() == KINDS(k) .and. shaped .and. exact, &
                &'minval of the whole, kept: (1, 1), the same')
            r = maxval(a, [1, 2])
            shaped = has_shape(r, [integer ::])
            exact = holds(r, lo, KINDS(k), .true.)
            call assert_true(r%kind() == KINDS(k) .and. shaped .and. exact, &
                &'maxval over the list [1, 2]: rank 0, the same')
            r = minval(a, [1], keepdims=.true.)
            shaped = has_shape(r, [1, 3])
            exact = holds(r, hi, KINDS(k), .false.)
            call assert_true(r%kind() == KINDS(k) .and. shaped .and. exact, &
                &'minval over the list [1], kept: (1, 3), the same')
            r = maxval(a, 2)
            shaped = has_shape(r, [0])
            call assert_true(r%kind() == KINDS(k) .and. shaped, &
                &'maxval over the nonzero dimension 2 of a (0, 3) array: an empty (0) result')
        end do
    contains
        ! whether every element of res equals the identity, exactly: integer kinds in int64 (the unsigned maximum as
        ! its bits, -1), the floating kinds and booleans through float32 (float64 itself), where they are exact
        logical function holds( res, want, kind, low )
            type(mlx_array), intent(in) :: res
            real(real64),    intent(in) :: want
            integer,         intent(in) :: kind
            logical,         intent(in) :: low
            integer(int64), allocatable :: iv(:)
            integer(int64)              :: wi
            integer                     :: n
            n = int(res%size())
            holds = n > 0
            if( .not. holds ) return
            if( any(kind == [MLX_DTYPES%int8, MLX_DTYPES%int16, MLX_DTYPES%int32, MLX_DTYPES%int64, MLX_DTYPES%uint8, &
                &MLX_DTYPES%uint16, MLX_DTYPES%uint32, MLX_DTYPES%uint64]) )then
                allocate(iv(n))
                call mlx_to(iv, mlx_astype(reshape(res, [n]), MLX_DTYPES%int64))
                select case( kind )
                    case( MLX_DTYPES%int8 )
                        wi = merge(-128_int64, 127_int64, low)
                    case( MLX_DTYPES%int16 )
                        wi = merge(-32768_int64, 32767_int64, low)
                    case( MLX_DTYPES%int32 )
                        wi = merge(-2147483648_int64, 2147483647_int64, low)
                    case( MLX_DTYPES%int64 )
                        wi = merge(-huge(1_int64)-1_int64, huge(1_int64), low)
                    case( MLX_DTYPES%uint8 )
                        wi = merge(0_int64, 255_int64, low)
                    case( MLX_DTYPES%uint16 )
                        wi = merge(0_int64, 65535_int64, low)
                    case( MLX_DTYPES%uint32 )
                        wi = merge(0_int64, 4294967295_int64, low)
                    case default
                        wi = merge(0_int64, -1_int64, low)
                end select
                holds = all(iv == wi)
            else
                call values_of(res, y)
                if( kind == MLX_DTYPES%float64 )then
                    holds = all(abs(y-want) <= 0._real64)
                else
                    holds = all(abs(y-real(real(want, real32), real64)) <= 0._real64)
                endif
            endif
        end function holds

    end subroutine test_empty_extrema

    ! the error of r against ref, both divided by s, as the family measures it; err keeps the largest
    subroutine scaled_error( r, ref, s, err )
        type(mlx_array), intent(in)    :: r
        real(real64),    intent(in)    :: ref(:), s
        real(real64),    intent(inout) :: err
        real(real64), allocatable :: y(:)
        call values_of(r, y)
        if( size(y) /= size(ref) )then
            err = huge(1._real64)
            return
        endif
        err = nan_max(err, nan_maxval(abs(y/s-ref/s)/max(1._real64, abs(ref/s))))
    end subroutine scaled_error

    ! the forms every scan runs: each dimension and the whole array, forward and reversed, inclusive and exclusive
    subroutine scan_forms( forms )
        type(reduce_form), allocatable, intent(out) :: forms(:)
        integer :: d, v
        allocate(forms(16))
        do d = 0, 3
            do v = 0, 3
                forms(4*d+v+1) = reduce_form(merge(FORM_ALL, FORM_DIM, d == 0), [d, 0, 0], min(d, 1), maps=.true.)
                forms(4*d+v+1)%reverse = mod(v, 2) == 1
                forms(4*d+v+1)%inclusive = v < 2
            end do
        end do
    end subroutine scan_forms

    ! every scan against its oracle on each seed: float32, and float64 on the CPU
    subroutine test_scan_family
        type(reduce_case)              :: cases(5)
        type(reduce_form), allocatable :: forms(:)
        integer,           allocatable :: seeds(:)
        real(real64)                   :: x(N1, N2, N3, NB)
        integer                        :: c, k
        write(*,'(a)') 'test_scan_family'
        cases(1) = reduce_case('mlx_cumsum', s_cumsum, o_cumsum, -2._real64, 2._real64, .false., .false.)
        cases(2) = reduce_case('mlx_cumprod', s_cumprod, o_cumprod, 0.5_real64, 1.5_real64, .false., .false.)
        cases(3) = reduce_case('mlx_cummax', s_cummax, o_cummax, -2._real64, 2._real64, .false., .true.)
        cases(4) = reduce_case('mlx_cummin', s_cummin, o_cummin, -2._real64, 2._real64, .false., .true.)
        cases(5) = reduce_case('mlx_logcumsumexp', s_logcumsumexp, o_logcumsumexp, -3._real64, 3._real64, .false., .false.)
        call scan_forms(forms)
        seeds = family_seeds()
        do k = 1, size(seeds)
            do c = 1, size(cases)
                call draw(x, cases(c)%lo, cases(c)%hi, 2000*seeds(k)+100+c, .false.)
                call run_case(cases(c), x, .false., forms, seeds(k))
                if( mlx_default_device() == MLX_DEVICES%cpu ) call run_case(cases(c), x, .true., forms, seeds(k))
            end do
        end do
    end subroutine test_scan_family

    ! the softmax along each dimension, over lists and by default (dimension 1), plain and precise
    subroutine test_softmax
        type(reduce_form)            :: forms(6)
        type(elem_tolerance)         :: tol
        type(mlx_array), allocatable :: both(:)
        type(mlx_array)              :: a, r
        integer,         allocatable :: seeds(:)
        real(real64),    allocatable :: ref(:)
        real(real64)                 :: x(N1, N2, N3, NB), err(2)
        integer                      :: k, j, p, passes
        write(*,'(a)') 'test_softmax'
        forms(1) = reduce_form(FORM_DIM, [1, 0, 0], 1, maps=.true.)
        forms(2) = reduce_form(FORM_DIM, [2, 0, 0], 1, maps=.true.)
        forms(3) = reduce_form(FORM_DIM, [3, 0, 0], 1, maps=.true.)
        forms(4) = reduce_form(FORM_DIMS, [1, 2, 0], 2, maps=.true.)
        forms(5) = reduce_form(FORM_DIMS, [3, 2, 0], 2, maps=.true.)
        forms(6) = reduce_form(FORM_DIMS, [1, 2, 3], 3, maps=.true.)
        tol = tolerance_of('mlx_softmax')
        seeds = family_seeds()
        passes = 1
        if( mlx_default_device() == MLX_DEVICES%cpu ) passes = 2
        do k = 1, size(seeds)
            call draw(x, -3._real64, 3._real64, 2000*seeds(k)+200, .false.)
            err = 0._real64
            do p = 1, passes
                call operands(x, p == 2, both)
                a = both(1)
                do j = 1, size(forms)
                    call batch_reference(x, forms(j), o_softmax, ref)
                    if( forms(j)%mode == FORM_DIM )then
                        r = mlx_softmax(a, forms(j)%dims(1))
                        err(p) = max(err(p), rel_error(r, ref))
                        r = mlx_softmax(a, forms(j)%dims(1), precise=.true.)
                    else
                        r = mlx_softmax(a, forms(j)%dims(:forms(j)%n))
                        err(p) = max(err(p), rel_error(r, ref))
                        r = mlx_softmax(a, forms(j)%dims(:forms(j)%n), precise=.true.)
                    endif
                    err(p) = max(err(p), rel_error(r, ref))
                end do
                call batch_reference(x, forms(1), o_softmax, ref)
                r = mlx_softmax(a)
                err(p) = max(err(p), rel_error(r, ref))
            end do
            call judge(err(1), tol%f32, 'mlx_softmax', 'float32', seeds(k))
            if( passes == 2 ) call judge(err(2), tol%f64, 'mlx_softmax', 'float64', seeds(k))
        end do
        a = mlx_from([1._real32, 2._real32, 4._real32])
        r = mlx_softmax(a)
        call reference(reshape([1._real64, 2._real64, 4._real64], [3, 1, 1]), forms(1), o_softmax, ref)
        call assert_true(rel_error(r, ref) <= tol%f32, 'mlx_softmax of a rank-1 array without a dimension is its softmax')
    end subroutine test_softmax

    ! maxloc and minloc along each dimension (1-based int32, the first on ties) and of the whole array (its
    ! subscripts), on whole numbers so that ties occur
    subroutine test_positions
        type(reduce_form)         :: form
        type(mlx_array)           :: a, r, total
        real(real64), allocatable :: ref(:), y(:)
        real(real64)              :: x(N1, N2, N3), x4(N1, N2, N3, 1)
        integer(int32)            :: sub(3)
        integer                   :: d, kept(3)
        write(*,'(a)') 'test_positions'
        call draw(x4, 0._real64, 3._real64, 77, .true.)
        x = x4(:, :, :, 1)
        a = mlx_from(real(x, real32))
        do d = 1, 3
            form = reduce_form(FORM_DIM, [d, 0, 0], 1)
            call reference(x, form, o_maxloc, ref)
            r = maxloc(a, d)
            call assert_true(rel_error(r, ref) <= 0._real64, 'maxloc(a, dim) is the 1-based position of the first maximum')
            call assert_int(MLX_DTYPES%int32, r%kind(), 'maxloc(a, dim) is int32')
            call reference(x, form, o_minloc, ref)
            r = minloc(a, d)
            call assert_true(rel_error(r, ref) <= 0._real64, 'minloc(a, dim) is the 1-based position of the first minimum')
            kept = [N1, N2, N3]
            kept(d) = 1
            r = maxloc(a, d, keepdims=.true.)
            call assert_true(has_shape(r, kept), 'maxloc(a, dim, keepdims) keeps dimension dim with extent 1')
            r = minloc(a, d, keepdims=.true.)
            call assert_true(has_shape(r, kept), 'minloc(a, dim, keepdims) keeps dimension dim with extent 1')
        end do
        r = maxloc(a)
        call assert_true(has_shape(r, [3]), 'maxloc(a) has one subscript per dimension')
        call assert_int(MLX_DTYPES%int32, r%kind(), 'maxloc(a) is int32')
        call mlx_to(sub, r)
        call assert_true(all(sub == maxloc(x)), 'maxloc(a) is the subscripts of the first maximum in array element order')
        r = minloc(a)
        call mlx_to(sub, r)
        call assert_true(all(sub == minloc(x)), 'minloc(a) is the subscripts of the first minimum in array element order')
        call assert_true(count(x >= maxval(x)) > 1 .and. count(x <= minval(x)) > 1, 'the fixture has tied extrema')
        a = mlx_zeros([0, 4])
        r = maxloc(a, 1)
        total = sum(r)
        call values_of(total, y)
        call assert_true(has_shape(r, [4]) .and. nint(y(1)) == 0, 'maxloc of a zero-size dimension is zero, as Fortran''s')
        r = maxloc(a)
        call mlx_to(sub(1:2), r)
        call assert_true(all(sub(1:2) == 0), 'maxloc of a zero-size array is zero in every subscript, as Fortran''s')
    end subroutine test_positions

    ! the conventions by name: kinds, ddof, the scan's exclusive start and rank-0 results
    subroutine test_reduce_conventions
        type(mlx_array)           :: a, r, i, mask, forward, gap
        real(real64), allocatable :: y(:)
        real(real64)              :: x(N1, N2, N3), x4(N1, N2, N3, 1), v, m
        write(*,'(a)') 'test_reduce_conventions'
        call draw(x4, -2._real64, 2._real64, 78, .false.)
        x = x4(:, :, :, 1)
        a = mlx_from(real(x, real32))
        r = sum(a)
        call assert_int(0, r%ndim(), 'a reduction over every dimension is rank 0')
        mask = a > 0._real32
        r = count(mask)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'count is int32')
        call values_of(r, y)
        call assert_true(nint(y(1)) == count(x > 0._real64), 'count of a mask counts its true elements')
        r = all(mask, 1)
        call assert_int(MLX_DTYPES%bool, r%kind(), 'all is boolean')
        r = any(mask, [1, 2])
        call assert_int(MLX_DTYPES%bool, r%kind(), 'any is boolean')
        i = mlx_astype(a, MLX_DTYPES%int32)
        r = mlx_mean(i)
        call assert_int(MLX_DTYPES%float32, r%kind(), 'the mean of an integer array is float32')
        r = sum(i, 1)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'the sum of an int32 array is int32')
        m = sum(x)/size(x)
        v = sum((x-m)**2)/(size(x)-1)
        r = mlx_var(a, ddof=1)
        call values_of(r, y)
        call assert_true(abs(y(1)-v) <= 1.e-5_real64*max(1._real64, v), 'mlx_var(ddof=1) divides by the count less one')
        r = mlx_std(a, ddof=1)
        call values_of(r, y)
        call assert_true(abs(y(1)-sqrt(v)) <= 1.e-5_real64*max(1._real64, sqrt(v)), 'mlx_std(ddof=1) is the root of that variance')
        r = mlx_cumsum(a, 1, inclusive=.false.)
        call values_of(r, y)
        call assert_true(all(abs(y(1:size(y):N1)) <= 0._real64), 'an exclusive running sum starts at zero')
        r = mlx_cumprod(a, 1, inclusive=.false.)
        call values_of(r, y)
        call assert_true(all(abs(y(1:size(y):N1)-1._real64) <= 0._real64), 'an exclusive running product starts at one')
        r = mlx_cumsum(a, 3, reverse=.true.)
        forward = mlx_cumsum(a, 3)
        gap = sum(abs(r-forward))
        call values_of(gap, y)
        call assert_true(y(1) > 0._real64, 'a reversed scan differs from the forward one (negative control)')
    end subroutine test_reduce_conventions

    function r_sum( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = sum(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = sum(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = sum(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_sum

    function r_product( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = product(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = product(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = product(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_product

    function r_maxval( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = maxval(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = maxval(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = maxval(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_maxval

    function r_minval( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = minval(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = minval(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = minval(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_minval

    function r_all( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = all(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = all(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = all(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_all

    function r_any( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = any(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = any(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = any(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_any

    function r_count( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = count(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = count(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = count(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_count

    function r_mean( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = mlx_mean(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = mlx_mean(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = mlx_mean(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_mean

    function r_median( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = mlx_median(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = mlx_median(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = mlx_median(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_median

    function r_var( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = mlx_var(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = mlx_var(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = mlx_var(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_var

    function r_std( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = mlx_std(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = mlx_std(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = mlx_std(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_std

    function r_logsumexp( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        select case( form%mode )
            case( FORM_ALL )
                r = mlx_logsumexp(a, keepdims=form%keepdims)
            case( FORM_DIM )
                r = mlx_logsumexp(a, form%dims(1), keepdims=form%keepdims)
            case default
                r = mlx_logsumexp(a, form%dims(:form%n), keepdims=form%keepdims)
        end select
    end function r_logsumexp

    function s_cumsum( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        if( form%mode == FORM_ALL )then
            r = mlx_cumsum(a, reverse=form%reverse, inclusive=form%inclusive)
        else
            r = mlx_cumsum(a, form%dims(1), reverse=form%reverse, inclusive=form%inclusive)
        endif
    end function s_cumsum

    function s_cumprod( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        if( form%mode == FORM_ALL )then
            r = mlx_cumprod(a, reverse=form%reverse, inclusive=form%inclusive)
        else
            r = mlx_cumprod(a, form%dims(1), reverse=form%reverse, inclusive=form%inclusive)
        endif
    end function s_cumprod

    function s_cummax( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        if( form%mode == FORM_ALL )then
            r = mlx_cummax(a, reverse=form%reverse, inclusive=form%inclusive)
        else
            r = mlx_cummax(a, form%dims(1), reverse=form%reverse, inclusive=form%inclusive)
        endif
    end function s_cummax

    function s_cummin( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        if( form%mode == FORM_ALL )then
            r = mlx_cummin(a, reverse=form%reverse, inclusive=form%inclusive)
        else
            r = mlx_cummin(a, form%dims(1), reverse=form%reverse, inclusive=form%inclusive)
        endif
    end function s_cummin

    function s_logcumsumexp( a, form ) result(r)
        type(mlx_array),   intent(in) :: a
        type(reduce_form), intent(in) :: form
        type(mlx_array) :: r
        if( form%mode == FORM_ALL )then
            r = mlx_logcumsumexp(a, reverse=form%reverse, inclusive=form%inclusive)
        else
            r = mlx_logcumsumexp(a, form%dims(1), reverse=form%reverse, inclusive=form%inclusive)
        endif
    end function s_logcumsumexp

    subroutine o_sum( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = sum(x)
    end subroutine o_sum

    subroutine o_product( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = product(x)
    end subroutine o_product

    subroutine o_maxval( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = maxval(x)
    end subroutine o_maxval

    subroutine o_minval( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = minval(x)
    end subroutine o_minval

    subroutine o_all( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = merge(1._real64, 0._real64, all(abs(x) > 0._real64))
    end subroutine o_all

    subroutine o_any( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = merge(1._real64, 0._real64, any(abs(x) > 0._real64))
    end subroutine o_any

    subroutine o_count( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = real(count(abs(x) > 0._real64), real64)
    end subroutine o_count

    subroutine o_mean( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = sum(x)/size(x)
    end subroutine o_mean

    ! the middle element of the sorted values, or the mean of the two middle ones
    subroutine o_median( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        real(real64) :: s(size(x)), t
        integer      :: i, j, n
        s = x
        n = size(x)
        do i = 2, n
            t = s(i)
            j = i-1
            do while( j >= 1 )
                if( s(j) <= t ) exit
                s(j+1) = s(j)
                j = j-1
            end do
            s(j+1) = t
        end do
        if( mod(n, 2) == 1 )then
            y(1) = s((n+1)/2)
        else
            y(1) = 0.5_real64*(s(n/2)+s(n/2+1))
        endif
    end subroutine o_median

    subroutine o_var( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        real(real64) :: m
        m = sum(x)/size(x)
        y(1) = sum((x-m)**2)/size(x)
    end subroutine o_var

    subroutine o_std( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        call o_var(x, y)
        y(1) = sqrt(y(1))
    end subroutine o_std

    subroutine o_logsumexp( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        real(real64) :: m
        m = maxval(x)
        y(1) = m+log(sum(exp(x-m)))
    end subroutine o_logsumexp

    subroutine o_maxloc( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = real(maxloc(x, dim=1), real64)
    end subroutine o_maxloc

    subroutine o_minloc( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        y(1) = real(minloc(x, dim=1), real64)
    end subroutine o_minloc

    subroutine o_cumsum( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        integer :: i
        do i = 1, size(x)
            y(i) = sum(x(1:i))
        end do
    end subroutine o_cumsum

    subroutine o_cumprod( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        integer :: i
        do i = 1, size(x)
            y(i) = product(x(1:i))
        end do
    end subroutine o_cumprod

    subroutine o_cummax( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        integer :: i
        do i = 1, size(x)
            y(i) = maxval(x(1:i))
        end do
    end subroutine o_cummax

    subroutine o_cummin( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        integer :: i
        do i = 1, size(x)
            y(i) = minval(x(1:i))
        end do
    end subroutine o_cummin

    subroutine o_logcumsumexp( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        real(real64) :: m
        integer      :: i
        do i = 1, size(x)
            m = maxval(x(1:i))
            y(i) = m+log(sum(exp(x(1:i)-m)))
        end do
    end subroutine o_logcumsumexp

    subroutine o_softmax( x, y )
        real(real64), intent(in)  :: x(:)
        real(real64), intent(out) :: y(:)
        real(real64) :: m
        m = maxval(x)
        y = exp(x-m)/sum(exp(x-m))
    end subroutine o_softmax

end module mlxf_ops_reduce_tester
