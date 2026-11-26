!@descr: the gathered, block-masked and segmented matrix products against Fortran's matmul on the selected blocks
! Seeded float32 operands on every device (float64 too for the segmented product on the CPU, the one MLX
! evaluates there in float64). The reference is real64 matmul of the sections a form selects: the matrices an
! index names, the blocks a mask keeps, the columns and rows a segment bounds. A result is judged by its largest
! error relative to max(1, (|a| |b|)(i, j)), the scale of a dot product's rounding; what a mask or an empty
! segment removes is exactly zero.
module mlxf_linalg_mm_tester
use, intrinsic :: iso_c_binding,   only: c_bool
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DEVICES, &
                            MLX_DTYPES, matmul, mlx_astype, mlx_gather_mm, mlx_block_masked_mm, mlx_segmented_mm
use mlxf_test_utils,  only: assert_true, test_devices, device_name, set_fixed_seed, bits_equal, judge_error, &
                            find_tolerance
use mlxf_test_defs,   only: ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED, ELEM_CEILING, MM_TOLERANCES, elem_tolerance
use mlxf_test_reduce, only: nan_maxval, nan_max
implicit none
private
public :: run_all_linalg_mm_tests

! the masked product's extents: three blocks of 32 rows, two of the inner dimension, four of columns, so that no
! mask is square
integer, parameter :: BM = 70, BK = 40, BN = 100, BLOCK = 32

! what the forms of one function gave: the largest error, whether every result had its expected shape, and
! whether everything a mask or an empty segment removes was exactly zero
type :: form_result
    real(real64) :: err    = 0._real64
    logical      :: shaped = .true.
    logical      :: zeroed = .true.
end type form_result

contains

    subroutine run_all_linalg_mm_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all linalg_mm tests ****'
        call assert_true(all(MM_TOLERANCES%f32 <= ELEM_CEILING), &
            &'every frozen float32 tolerance of a matrix product is within the ceiling of 64 float32 epsilons')
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_gather_mm
            call test_block_masked_mm
            call test_segmented_mm
            call test_product_conventions
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_linalg_mm_tests

    ! the seeds every family runs: the calibration seed, then the judged ones
    function family_seeds() result(seeds)
        integer, allocatable :: seeds(:)
        seeds = [ELEM_SEED_CALIBRATION, ELEM_SEEDS_JUDGED]
    end function family_seeds

    ! n values from a fixed seed, uniform in [-1, 1] and rounded once to float32
    function drawn( n, seed ) result(x)
        integer, intent(in) :: n, seed
        real(real64) :: x(n)
        call set_fixed_seed(seed)
        call random_number(x)
        x = real(real(2*x-1, real32), real64)
    end function drawn

    ! n whole numbers from a fixed seed, uniform in 1 to top
    function drawn_indices( n, top, seed ) result(k)
        integer, intent(in) :: n, top, seed
        integer(int32) :: k(n)
        real(real64)   :: u(n)
        call set_fixed_seed(seed)
        call random_number(u)
        k = int(1+min(top-1, int(top*u)), int32)
    end function drawn_indices

    ! a float32 result against its reference: the shape first, then the largest error relative to
    ! max(1, bound), and exact zeros wherever the bound is zero
    subroutine compare( r, want, ref, bound, res )
        type(mlx_array),   intent(in)    :: r
        integer,           intent(in)    :: want(:)
        real(real64),      intent(in)    :: ref(:), bound(:)
        type(form_result), intent(inout) :: res
        real(real32), allocatable :: got(:)
        integer,      allocatable :: sh(:)
        integer                   :: st
        sh = r%shape()
        if( size(sh) /= size(want) )then
            res%shaped = .false.
            return
        endif
        if( any(sh /= want) )then
            res%shaped = .false.
            return
        endif
        allocate(got(size(ref)))
        call mlx_to(got, r, status=st)
        if( st /= 0 )then
            res%shaped = .false.
            return
        endif
        res%err = nan_max(res%err, nan_maxval(abs(real(got, real64)-ref)/max(1._real64, bound)))
        if( any(bound <= 0._real64 .and. abs(got) > 0._real32) ) res%zeroed = .false.
    end subroutine compare

    ! the products of matrices chosen by 1-based numbers in array element order over the batch dimensions: rank-1
    ! lists (uint64 and int64), lists that broadcast, one list with the other operand's matrices in order, and a
    ! sorted list against matrices of one column, the case MLX's sorted route serves
    subroutine test_gather_mm
        integer, parameter   :: M = 5, K = 4, N = 6, NA = 6, NB = 5, NSEL = 7
        integer, allocatable :: seeds(:)
        type(mlx_array)      :: a, b, r
        type(elem_tolerance) :: tol
        type(form_result)    :: res
        real(real64)         :: x(M, K, 3, 2), xf(M, K, NA), y(K, N, NB)
        real(real64)         :: ref1(M, N, NSEL), bound1(M, N, NSEL), ref2(M, N, 3, 4), bound2(M, N, 3, 4)
        real(real64)         :: ref3(M, N, NB), bound3(M, N, NB), ref4(M, N, 3, 2), bound4(M, N, 3, 2)
        real(real64)         :: ref5(M, 1, NB), bound5(M, 1, NB)
        integer(int32)       :: lhs(NSEL), rhs(NSEL), lhs2(3, 1), rhs2(1, 4), lhs5(NB), rhs4(3, 2)
        integer              :: s, i, j
        write(*,'(a)') 'test_gather_mm'
        tol = find_tolerance(MM_TOLERANCES, 'mlx_gather_mm')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(drawn(size(x), 4000*seeds(s)+1), shape(x))
            y = reshape(drawn(size(y), 4000*seeds(s)+2), shape(y))
            xf = reshape(x, shape(xf))
            lhs = drawn_indices(NSEL, NA, 4000*seeds(s)+3)
            rhs = drawn_indices(NSEL, NB, 4000*seeds(s)+4)
            lhs2 = reshape(drawn_indices(3, NA, 4000*seeds(s)+5), shape(lhs2))
            rhs2 = reshape(drawn_indices(4, NB, 4000*seeds(s)+6), shape(rhs2))
            rhs4 = reshape(drawn_indices(6, NB, 4000*seeds(s)+7), shape(rhs4))
            lhs5 = [1_int32, 2_int32, 2_int32, 4_int32, 6_int32]
            do i = 1, NSEL
                ref1(:, :, i) = matmul(xf(:, :, lhs(i)), y(:, :, rhs(i)))
                bound1(:, :, i) = matmul(abs(xf(:, :, lhs(i))), abs(y(:, :, rhs(i))))
            end do
            do j = 1, 4
                do i = 1, 3
                    ref2(:, :, i, j) = matmul(xf(:, :, lhs2(i, 1)), y(:, :, rhs2(1, j)))
                    bound2(:, :, i, j) = matmul(abs(xf(:, :, lhs2(i, 1))), abs(y(:, :, rhs2(1, j))))
                end do
            end do
            do i = 1, NB
                ref3(:, :, i) = matmul(xf(:, :, lhs5(i)), y(:, :, i))
                bound3(:, :, i) = matmul(abs(xf(:, :, lhs5(i))), abs(y(:, :, i)))
                ref5(:, :, i) = matmul(xf(:, :, lhs5(i)), y(:, 2:2, i))
                bound5(:, :, i) = matmul(abs(xf(:, :, lhs5(i))), abs(y(:, 2:2, i)))
            end do
            do j = 1, 2
                do i = 1, 3
                    ref4(:, :, i, j) = matmul(x(:, :, i, j), y(:, :, rhs4(i, j)))
                    bound4(:, :, i, j) = matmul(abs(x(:, :, i, j)), abs(y(:, :, rhs4(i, j))))
                end do
            end do
            a = mlx_from(real(x, real32))
            b = mlx_from(real(y, real32))
            res = form_result()
            r = mlx_gather_mm(a, b, lhs_indices=mlx_astype(mlx_from(lhs), MLX_DTYPES%uint64), rhs_indices=mlx_from(int(rhs, int64)))
            call compare(r, [M, N, NSEL], reshape(ref1, [size(ref1)]), reshape(bound1, [size(bound1)]), res)
            r = mlx_gather_mm(a, b, lhs_indices=mlx_from(lhs2), rhs_indices=mlx_from(rhs2))
            call compare(r, [M, N, 3, 4], reshape(ref2, [size(ref2)]), reshape(bound2, [size(bound2)]), res)
            r = mlx_gather_mm(a, b, lhs_indices=mlx_from(lhs5), sorted_indices=.true.)
            call compare(r, [M, N, NB], reshape(ref3, [size(ref3)]), reshape(bound3, [size(bound3)]), res)
            r = mlx_gather_mm(a, b, rhs_indices=mlx_from(rhs4))
            call compare(r, [M, N, 3, 2], reshape(ref4, [size(ref4)]), reshape(bound4, [size(bound4)]), res)
            b = mlx_from(real(y(:, 2:2, :), real32))
            r = mlx_gather_mm(a, b, lhs_indices=mlx_from(lhs5), sorted_indices=.true.)
            call compare(r, [M, 1, NB], reshape(ref5, [size(ref5)]), reshape(bound5, [size(bound5)]), res)
            call judge_error(res%err, tol%f32, 'mlx_gather_mm', 'float32', seeds(s))
            call assert_true(res%shaped, 'mlx_gather_mm: the result is (rows of a, columns of b, the index arrays'' broadcast shape)')
        end do
    end subroutine test_gather_mm

    ! the element weights of a block mask over an (n1, n2) matrix: element (i, j) takes the mask's value for its
    ! block
    function block_weights( mask, n1, n2, block ) result(w)
        real(real64), intent(in) :: mask(:,:)
        integer,      intent(in) :: n1, n2, block
        real(real64) :: w(n1, n2)
        integer      :: i, j
        do j = 1, n2
            do i = 1, n1
                w(i, j) = mask((i-1)/block+1, (j-1)/block+1)
            end do
        end do
    end function block_weights

    ! a block mask of ones and zeros from a fixed seed, about two blocks in three kept, the first kept and the last
    ! dropped so that both occur
    function drawn_mask( n1, n2, seed ) result(mask)
        integer, intent(in) :: n1, n2, seed
        real(real64) :: mask(n1, n2), u(n1, n2)
        call set_fixed_seed(seed)
        call random_number(u)
        mask = merge(1._real64, 0._real64, u < 0.67_real64)
        mask(1, 1) = 1
        mask(n1, n2) = 0
    end function drawn_mask

    ! the product with blocks of 32 left out of the result, of the operands, of both; the default block of 64, whose
    ! (2, 2) mask drops block (1, 2) alone; a real mask that scales its blocks; a batch of two products with a mask each
    subroutine test_block_masked_mm
        integer,      allocatable :: seeds(:)
        type(mlx_array)           :: a, b, r, masks(2)
        type(elem_tolerance)      :: tol
        type(form_result)         :: res
        real(real64)              :: x(BM, BK, 2), y(BK, BN, 2), ref(BM, BN, 2), bound(BM, BN, 2)
        real(real64)              :: mo(3, 4, 2), ma(3, 2), mb(2, 4), mo64(2, 2), wo(BM, BN), wa(BM, BK), wb(BK, BN)
        integer                   :: s, p
        write(*,'(a)') 'test_block_masked_mm'
        tol = find_tolerance(MM_TOLERANCES, 'mlx_block_masked_mm')
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(drawn(size(x), 4100*seeds(s)+1), shape(x))
            y = reshape(drawn(size(y), 4100*seeds(s)+2), shape(y))
            mo(:, :, 1) = drawn_mask(3, 4, 4100*seeds(s)+3)
            mo(:, :, 2) = drawn_mask(3, 4, 4100*seeds(s)+4)
            ma = drawn_mask(3, 2, 4100*seeds(s)+5)
            mb = drawn_mask(2, 4, 4100*seeds(s)+6)
            mo64 = reshape([1._real64, 1._real64, 0._real64, 1._real64], shape(mo64))
            a = mlx_from(real(x(:, :, 1), real32))
            b = mlx_from(real(y(:, :, 1), real32))
            masks(1) = mlx_from(logical(ma > 0.5_real64, c_bool))
            masks(2) = mlx_from(logical(mb > 0.5_real64, c_bool))
            wo = block_weights(mo(:, :, 1), BM, BN, BLOCK)
            wa = block_weights(ma, BM, BK, BLOCK)
            wb = block_weights(mb, BK, BN, BLOCK)
            res = form_result()
            r = mlx_block_masked_mm(a, b, block_size=BLOCK, mask_out=mlx_from(logical(mo(:, :, 1) > 0.5_real64, c_bool)))
            ref(:, :, 1) = wo*matmul(x(:, :, 1), y(:, :, 1))
            bound(:, :, 1) = wo*matmul(abs(x(:, :, 1)), abs(y(:, :, 1)))
            call compare(r, [BM, BN], reshape(ref(:, :, 1), [BM*BN]), reshape(bound(:, :, 1), [BM*BN]), res)
            r = mlx_block_masked_mm(a, b, block_size=BLOCK, operand_masks=masks)
            ref(:, :, 1) = matmul(wa*x(:, :, 1), wb*y(:, :, 1))
            bound(:, :, 1) = matmul(wa*abs(x(:, :, 1)), wb*abs(y(:, :, 1)))
            call compare(r, [BM, BN], reshape(ref(:, :, 1), [BM*BN]), reshape(bound(:, :, 1), [BM*BN]), res)
            r = mlx_block_masked_mm(a, b, block_size=BLOCK, mask_out=mlx_from(logical(mo(:, :, 1) > 0.5_real64, c_bool)), operand_masks=masks)
            ref(:, :, 1) = wo*ref(:, :, 1)
            bound(:, :, 1) = wo*bound(:, :, 1)
            call compare(r, [BM, BN], reshape(ref(:, :, 1), [BM*BN]), reshape(bound(:, :, 1), [BM*BN]), res)
            r = mlx_block_masked_mm(a, b, mask_out=mlx_from(logical(mo64 > 0.5_real64, c_bool)))
            wo = block_weights(mo64, BM, BN, 64)
            ref(:, :, 1) = wo*matmul(x(:, :, 1), y(:, :, 1))
            bound(:, :, 1) = wo*matmul(abs(x(:, :, 1)), abs(y(:, :, 1)))
            call compare(r, [BM, BN], reshape(ref(:, :, 1), [BM*BN]), reshape(bound(:, :, 1), [BM*BN]), res)
            r = mlx_block_masked_mm(a, b, block_size=BLOCK, mask_out=mlx_from(real(0.5_real64+1.5_real64*mo(:, :, 2), real32)))
            wo = block_weights(0.5_real64+1.5_real64*mo(:, :, 2), BM, BN, BLOCK)
            ref(:, :, 1) = wo*matmul(x(:, :, 1), y(:, :, 1))
            bound(:, :, 1) = wo*matmul(abs(x(:, :, 1)), abs(y(:, :, 1)))
            call compare(r, [BM, BN], reshape(ref(:, :, 1), [BM*BN]), reshape(bound(:, :, 1), [BM*BN]), res)
            a = mlx_from(real(x, real32))
            b = mlx_from(real(y, real32))
            r = mlx_block_masked_mm(a, b, block_size=BLOCK, mask_out=mlx_from(logical(mo > 0.5_real64, c_bool)))
            do p = 1, 2
                wo = block_weights(mo(:, :, p), BM, BN, BLOCK)
                ref(:, :, p) = wo*matmul(x(:, :, p), y(:, :, p))
                bound(:, :, p) = wo*matmul(abs(x(:, :, p)), abs(y(:, :, p)))
            end do
            call compare(r, [BM, BN, 2], reshape(ref, [size(ref)]), reshape(bound, [size(bound)]), res)
            call judge_error(res%err, tol%f32, 'mlx_block_masked_mm', 'float32', seeds(s))
            call assert_true(res%shaped, 'mlx_block_masked_mm: the result has matmul''s shape, batches included')
            call assert_true(res%zeroed, 'mlx_block_masked_mm: a block that a mask drops is exactly zero')
        end do
    end subroutine test_block_masked_mm

    ! the product cut along the inner dimension by inclusive 1-based bounds: a list of segments, one of them
    ! reversed (9 to 2), and a (2, 2, 3) uint64 array of them; float32 on every device and float64 on the CPU
    subroutine test_segmented_mm
        integer,      parameter   :: M = 5, K = 12, N = 6
        integer,      allocatable :: seeds(:)
        type(mlx_array)           :: a, b, r
        type(elem_tolerance)      :: tol
        type(form_result)         :: res
        real(real64), allocatable :: got64(:)
        real(real64)              :: x(M, K), y(K, N), ref(M, N, 4), bound(M, N, 4), ref2(M, N, 2, 3), bound2(M, N, 2, 3)
        real(real64)              :: err64
        integer(int32)            :: segs(2, 4), segs2(2, 2, 3)
        integer                   :: s, i, j, st
        write(*,'(a)') 'test_segmented_mm'
        tol = find_tolerance(MM_TOLERANCES, 'mlx_segmented_mm')
        segs = reshape([1, 3, 4, 4, 5, 12, 9, 2], shape(segs))
        do j = 1, 3
            do i = 1, 2
                segs2(1, i, j) = int(1+modulo(i+3*j, K), int32)
                segs2(2, i, j) = int(min(K, segs2(1, i, j)+i+j), int32)
            end do
        end do
        seeds = family_seeds()
        do s = 1, size(seeds)
            x = reshape(drawn(size(x), 4200*seeds(s)+1), shape(x))
            y = reshape(drawn(size(y), 4200*seeds(s)+2), shape(y))
            do i = 1, 4
                ref(:, :, i) = matmul(x(:, segs(1, i):segs(2, i)), y(segs(1, i):segs(2, i), :))
                bound(:, :, i) = matmul(abs(x(:, segs(1, i):segs(2, i))), abs(y(segs(1, i):segs(2, i), :)))
            end do
            do j = 1, 3
                do i = 1, 2
                    ref2(:, :, i, j) = matmul(x(:, segs2(1, i, j):segs2(2, i, j)), y(segs2(1, i, j):segs2(2, i, j), :))
                    bound2(:, :, i, j) = matmul(abs(x(:, segs2(1, i, j):segs2(2, i, j))), abs(y(segs2(1, i, j):segs2(2, i, j), :)))
                end do
            end do
            a = mlx_from(real(x, real32))
            b = mlx_from(real(y, real32))
            res = form_result()
            r = mlx_segmented_mm(a, b, mlx_from(segs))
            call compare(r, [M, N, 4], reshape(ref, [size(ref)]), reshape(bound, [size(bound)]), res)
            r = mlx_segmented_mm(a, b, mlx_astype(mlx_from(segs2), MLX_DTYPES%uint64))
            call compare(r, [M, N, 2, 3], reshape(ref2, [size(ref2)]), reshape(bound2, [size(bound2)]), res)
            call judge_error(res%err, tol%f32, 'mlx_segmented_mm', 'float32', seeds(s))
            call assert_true(res%shaped, 'mlx_segmented_mm: the result is (rows of a, columns of b, the segments'' dimensions 2 and up)')
            call assert_true(res%zeroed, 'mlx_segmented_mm: a segment whose last index is below its first gives exact zeros')
            if( mlx_default_device() /= MLX_DEVICES%cpu ) cycle
            a = mlx_from(x)
            b = mlx_from(y)
            r = mlx_segmented_mm(a, b, mlx_from(segs))
            allocate(got64(size(ref)))
            call mlx_to(got64, r, status=st)
            err64 = huge(1._real64)
            if( st == 0 ) err64 = nan_maxval(abs(got64-reshape(ref, [size(ref)]))/max(1._real64, reshape(bound, [size(bound)])))
            deallocate(got64)
            call judge_error(err64, tol%f64, 'mlx_segmented_mm', 'float64', seeds(s))
        end do
    end subroutine test_segmented_mm

    ! by name: without indices and without masks the two products are matmul, bit for bit; the result's dtype is
    ! the operands'; a gathered matrix is numbered in array element order over the batch dimensions
    subroutine test_product_conventions
        type(mlx_array)      :: a, b, r, plain
        type(elem_tolerance) :: tol
        real(real64)         :: x(5, 4, 3, 2), y(4, 6, 3, 2), bound(5, 6)
        real(real32)         :: p(5, 6, 3, 2), q(5, 6, 3, 2), one(5, 6, 1)
        write(*,'(a)') 'test_product_conventions'
        tol = find_tolerance(MM_TOLERANCES, 'mlx_gather_mm')
        x = reshape(drawn(size(x), 7101), shape(x))
        y = reshape(drawn(size(y), 7102), shape(y))
        a = mlx_from(real(x, real32))
        b = mlx_from(real(y, real32))
        plain = matmul(a, b)
        call mlx_to(p, plain)
        r = mlx_gather_mm(a, b)
        call mlx_to(q, r)
        call assert_true(all(bits_equal(p, q)), 'mlx_gather_mm without indices is matmul, bit for bit')
        r = mlx_block_masked_mm(a, b)
        call mlx_to(q, r)
        call assert_true(all(bits_equal(p, q)), 'mlx_block_masked_mm without masks is matmul, bit for bit')
        call assert_true(r%kind() == MLX_DTYPES%float32, 'a product of float32 operands is float32')
        r = mlx_gather_mm(a, b, lhs_indices=mlx_from([4_int32]), rhs_indices=mlx_from([1_int32]))
        call mlx_to(one, r)
        bound = matmul(abs(x(:, :, 1, 2)), abs(y(:, :, 1, 1)))
        bound = max(1._real64, bound)
        call assert_true(all(abs(real(one(:, :, 1), real64)-matmul(x(:, :, 1, 2), y(:, :, 1, 1))) <= tol%f32*bound), 'matrix 4 of a (5, 4, 3, 2) array is a(:, :, 1, 2): array element order over dimensions 3 and 4')
        call assert_true(.not. all(abs(real(one(:, :, 1), real64)-matmul(x(:, :, 2, 2), y(:, :, 1, 1))) <= tol%f32*bound), 'the row-major matrix 4, a(:, :, 2, 2), gives another product')
    end subroutine test_product_conventions

end module mlxf_linalg_mm_tester
