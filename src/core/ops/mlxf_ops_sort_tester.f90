!@descr: two-device checks of sorting, partitioning and the largest elements against plain Fortran sorts
! A seeded (5, 4, 3) array of whole numbers, so that ties occur: every result is exact. Along each dimension and
! of the whole array in array element order; positions are 1-based int32 and kth is a 1-based position.
module mlxf_ops_sort_tester
use, intrinsic :: iso_fortran_env, only: int32, real32
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DTYPES, &
                           mlx_sort, mlx_argsort, mlx_partition, mlx_argpartition, mlx_topk
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name, set_fixed_seed
implicit none
private
public :: run_all_ops_sort_tests

integer, parameter :: N1 = 5, N2 = 4, N3 = 3

contains

    subroutine run_all_ops_sort_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all ops_sort tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_sort_along
            call test_sort_whole
            call test_partition
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_ops_sort_tests

    ! whether r is rank 1 with n elements
    logical function is_vector( r, n )
        type(mlx_array), intent(in) :: r
        integer,         intent(in) :: n
        is_vector = r%ndim() == 1
        if( is_vector ) is_vector = r%size() == n
    end function is_vector

    ! whole numbers of [0, top] from a fixed seed
    subroutine draw( x, top, seed )
        real(real32), intent(out) :: x(:,:,:)
        integer,      intent(in)  :: top, seed
        real :: u(size(x, 1), size(x, 2), size(x, 3))
        call set_fixed_seed(seed)
        call random_number(u)
        x = real(int(u*real(top+1)), real32)
    end subroutine draw

    ! the stable ascending order of v: the positions, equal elements in their original order
    function stable_order( v ) result(idx)
        real(real32), intent(in) :: v(:)
        integer :: idx(size(v))
        integer :: i, j, t
        idx = [(i, i=1, size(v))]
        do i = 2, size(v)
            t = idx(i)
            j = i-1
            do while( j >= 1 )
                if( v(idx(j)) <= v(t) ) exit
                idx(j+1) = idx(j)
                j = j-1
            end do
            idx(j+1) = t
        end do
    end function stable_order

    ! line number l of x along dimension d, the other two dimensions counted in array element order
    function line_of( x, d, l ) result(v)
        real(real32), intent(in) :: x(:,:,:)
        integer,      intent(in) :: d, l
        real(real32), allocatable :: v(:)
        integer                   :: n(3), a, b
        n = shape(x)
        select case( d )
            case( 1 )
                a = mod(l-1, n(2))+1
                b = (l-1)/n(2)+1
                v = x(:, a, b)
            case( 2 )
                a = mod(l-1, n(1))+1
                b = (l-1)/n(1)+1
                v = x(a, :, b)
            case default
                a = mod(l-1, n(1))+1
                b = (l-1)/n(1)+1
                v = x(a, b, :)
        end select
    end function line_of

    ! mlx_sort and mlx_argsort along each dimension
    subroutine test_sort_along
        type(mlx_array)           :: a, r
        real(real32)              :: x(N1, N2, N3), y(N1, N2, N3)
        integer(int32)            :: p(N1, N2, N3)
        real(real32), allocatable :: v(:), w(:)
        integer,      allocatable :: order(:)
        integer                   :: d, l, nl
        logical                   :: sorted, positions, stable
        write(*,'(a)') 'test_sort_along'
        call draw(x, 4, 301)
        a = mlx_from(x)
        do d = 1, 3
            nl = size(x)/size(x, d)
            r = mlx_sort(a, d)
            call mlx_to(y, r)
            r = mlx_argsort(a, d)
            call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_argsort gives int32 positions')
            call mlx_to(p, r)
            sorted = .true.
            positions = .true.
            stable = .true.
            do l = 1, nl
                v = line_of(x, d, l)
                order = stable_order(v)
                w = line_of(y, d, l)
                if( any(abs(w-v(order)) > 0._real32) ) sorted = .false.
                w = line_of(real(p, real32), d, l)
                if( any(nint(w) < 1) .or. any(nint(w) > size(v)) )then
                    positions = .false.
                else
                    if( any(abs(v(nint(w))-v(order)) > 0._real32) ) positions = .false.
                    if( any(nint(w) /= order) ) stable = .false.
                endif
            end do
            call assert_true(sorted, 'mlx_sort(a, dim) sorts every line along dim in ascending order')
            call assert_true(positions, 'mlx_argsort(a, dim) gives the 1-based positions that sort each line')
            call assert_true(stable, 'mlx_argsort keeps equal elements in their original order on this fixture')
        end do
    end subroutine test_sort_along

    ! without a dimension: the elements in array element order, a rank-1 result
    subroutine test_sort_whole
        type(mlx_array) :: a, r
        real(real32)    :: x(N1, N2, N3), flat(N1*N2*N3), y(N1*N2*N3), top(7)
        integer(int32)  :: p(N1*N2*N3)
        integer         :: order(N1*N2*N3), n
        write(*,'(a)') 'test_sort_whole'
        call draw(x, 9, 302)
        n = size(x)
        flat = reshape(x, [n])
        order = stable_order(flat)
        a = mlx_from(x)
        r = mlx_sort(a)
        call assert_true(is_vector(r, n), 'mlx_sort(a) is rank 1')
        call mlx_to(y, r)
        call assert_true(all(abs(y-flat(order)) <= 0._real32), 'mlx_sort(a) sorts the elements of the whole array')
        r = mlx_argsort(a)
        call mlx_to(p, r)
        call assert_true(all(p >= 1 .and. p <= n), 'mlx_argsort(a) gives positions from 1 to the size')
        call assert_true(all(abs(flat(p)-flat(order)) <= 0._real32), &
            &'mlx_argsort(a) gives positions in array element order that sort the array')
        r = mlx_topk(a, 7)
        call assert_true(is_vector(r, 7), 'mlx_topk(a, k) is rank 1 of size k')
        call mlx_to(top, r)
        call assert_true(all(abs(top(stable_order(top))-flat(order(n-6:n))) <= 0._real32), &
            &'mlx_topk(a, k) holds the k largest elements of the whole array')
    end subroutine test_sort_whole

    ! mlx_partition, mlx_argpartition and mlx_topk along each dimension, and the partitions of the whole array
    subroutine test_partition
        type(mlx_array)           :: a, r
        real(real32)              :: x(N1, N2, N3), y(N1, N2, N3), flat(N1*N2*N3), yf(N1*N2*N3)
        integer(int32)            :: p(N1, N2, N3), pf(N1*N2*N3)
        real(real32), allocatable :: v(:), w(:), s(:), t(:,:,:)
        integer,      allocatable :: q(:), ts(:)
        integer                   :: d, l, nl, kth, n
        logical                   :: parted, by_position, largest, wide
        write(*,'(a)') 'test_partition'
        call draw(x, 9, 303)
        a = mlx_from(x)
        do d = 1, 3
            nl = size(x)/size(x, d)
            kth = 2
            r = mlx_partition(a, kth, d)
            call mlx_to(y, r)
            r = mlx_argpartition(a, kth, d)
            call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_argpartition gives int32 positions')
            call mlx_to(p, r)
            ts = shape(x)
            ts(d) = 2
            allocate(t(ts(1), ts(2), ts(3)))
            r = mlx_topk(a, 2, d)
            wide = r%ndim() == 3
            if( wide ) wide = all(r%shape() == ts)
            call assert_true(wide, 'mlx_topk(a, k, dim) has extent k along dim')
            t = 0._real32
            if( wide ) call mlx_to(t, r)
            parted = .true.
            by_position = .true.
            largest = .true.
            do l = 1, nl
                v = line_of(x, d, l)
                s = v(stable_order(v))
                w = line_of(y, d, l)
                if( .not. is_partition(w, s, kth) ) parted = .false.
                q = nint(line_of(real(p, real32), d, l))
                if( any(q < 1) .or. any(q > size(v)) )then
                    by_position = .false.
                else if( .not. is_partition(v(q), s, kth) )then
                    by_position = .false.
                endif
                w = line_of(t, d, l)
                if( any(abs(w(stable_order(w))-s(size(s)-1:)) > 0._real32) ) largest = .false.
            end do
            deallocate(t)
            call assert_true(parted, 'mlx_partition(a, kth, dim) puts the kth smallest of each line at position kth, '// &
                &'nothing larger before it and nothing smaller after it')
            call assert_true(by_position, 'mlx_argpartition(a, kth, dim) gives 1-based positions that partition each line')
            call assert_true(largest, 'mlx_topk(a, k, dim) holds the k largest elements of each line')
        end do
        n = size(x)
        flat = reshape(x, [n])
        s = flat(stable_order(flat))
        r = mlx_partition(a, 10)
        call mlx_to(yf, r)
        call assert_true(is_partition(yf, s, 10), 'mlx_partition(a, kth) partitions the elements of the whole array')
        r = mlx_argpartition(a, 10)
        call mlx_to(pf, r)
        parted = all(pf >= 1 .and. pf <= n)
        if( parted ) parted = is_partition(flat(pf), s, 10)
        call assert_true(parted, 'mlx_argpartition(a, kth) gives positions in array element order')
    end subroutine test_partition

    ! whether w is a partition at position kth of the values whose sorted order is s
    logical function is_partition( w, s, kth )
        real(real32), intent(in) :: w(:), s(:)
        integer,      intent(in) :: kth
        is_partition = abs(w(kth)-s(kth)) <= 0._real32 .and. all(w(:kth) <= w(kth)) .and. all(w(kth:) >= w(kth))
        if( is_partition ) is_partition = all(abs(w(stable_order(w))-s) <= 0._real32)
    end function is_partition

end module mlxf_ops_sort_tester
