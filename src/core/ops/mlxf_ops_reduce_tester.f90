!@descr: table-driven two-device checks of the reductions, scans, softmax and extremum positions
! Each function runs on seeded (5, 4, 3) arrays, a batch of them along a fourth dimension, in every form (one
! dimension, a list, all of them) against a plain Fortran real64 oracle applied to the elements it reduces, taken
! in array element order: float32 on every device, float64 on the CPU. Float results are judged by the frozen
! tolerances of mlxf_test_defs (an error relative to max(1, |reference|)); extrema, logical reductions, counts
! and positions are exact.
module mlxf_ops_reduce_tester
use, intrinsic :: iso_fortran_env, only: int32, real32, real64
use, intrinsic :: ieee_arithmetic, only: ieee_is_nan, ieee_value, ieee_quiet_nan
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                            MLX_DTYPES, mlx_astype, mlx_zeros, reshape, sum, product, maxval, minval, all, any, count, &
                            mlx_mean, mlx_median, mlx_var, mlx_std, mlx_logsumexp, maxloc, minloc, mlx_cumsum, abs, &
                            mlx_cumprod, mlx_cummax, mlx_cummin, mlx_logcumsumexp, mlx_softmax
use mlxf_test_utils,  only: assert_true, assert_int, test_devices, device_name, set_fixed_seed
use mlxf_test_defs,   only: ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED, ELEM_CEILING, REDUCE_TOLERANCES, REDUCE_NBATCH, &
                            elem_tolerance
use mlxf_test_reduce, only: nan_maxval
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
