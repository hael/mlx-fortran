!@descr: two-device checks of gathers, scatters, section updates, searches and unique values against Fortran loops
! The fixture is a (2, 3, 4) array whose element (i, j, k) holds i + 10 j + 100 k, so that every result names the
! elements it took. Indices and positions are 1-based in every call; shapes and values are exact.
module mlxf_ops_index_tester
use, intrinsic :: iso_c_binding,   only: c_bool
use, intrinsic :: iso_fortran_env, only: int32, real32
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DTYPES, &
                           mlx_astype, reshape, mlx_take, mlx_take_along_dim, mlx_gather, mlx_scatter, mlx_scatter_add, &
                           mlx_scatter_max, mlx_scatter_min, mlx_scatter_prod, mlx_put_along_dim, mlx_masked_scatter, &
                           mlx_searchsorted, mlx_unique, mlx_slice, mlx_slice_update, mlx_slice_update_add, &
                           mlx_slice_update_max, mlx_slice_update_min, mlx_slice_update_prod
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name
implicit none
private
public :: run_all_ops_index_tests

integer, parameter :: N1 = 2, N2 = 3, N3 = 4

contains

    subroutine run_all_ops_index_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all ops_index tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_take_and_gather
            call test_scatter
            call test_along_dim
            call test_section_updates
            call test_search_and_unique
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_ops_index_tests

    ! element (i, j, k) is i + 10 j + 100 k
    subroutine fixture( x )
        real(real32), intent(out) :: x(N1, N2, N3)
        integer :: i, j, k
        do k = 1, N3
            do j = 1, N2
                do i = 1, N1
                    x(i, j, k) = real(i+10*j+100*k, real32)
                end do
            end do
        end do
    end subroutine fixture

    ! r has Fortran shape wshape and, in array element order, the values wflat
    subroutine expect( r, wshape, wflat, label )
        type(mlx_array),  intent(in) :: r
        integer,          intent(in) :: wshape(:)
        real(real32),     intent(in) :: wflat(:)
        character(len=*), intent(in) :: label
        type(mlx_array)      :: flat, f32
        real(real32)         :: y(size(wflat))
        integer, allocatable :: got(:)
        logical              :: same
        got = r%shape()
        same = size(got) == size(wshape)
        if( same ) same = all(got == wshape)
        if( same ) same = product(wshape) == size(wflat)
        if( same )then
            flat = reshape(r, [size(wflat)])
            f32 = mlx_astype(flat, MLX_DTYPES%float32)
            call mlx_to(y, f32)
            same = all(abs(y-wflat) <= 0._real32)
        endif
        call assert_true(same, label)
    end subroutine expect

    ! mlx_take without a dimension, mlx_gather with one and with two index arrays, the dynamic mlx_slice
    subroutine test_take_and_gather
        type(mlx_array) :: a, idx, jdx, r, start, wide
        real(real32)    :: x(N1, N2, N3), pair(1, 1, 4, 2), flat(N1*N2*N3)
        integer         :: p
        write(*,'(a)') 'test_take_and_gather'
        call fixture(x)
        a = mlx_from(x)
        flat = reshape(x, [size(x)])
        idx = mlx_from(reshape([1_int32, 24_int32, 3_int32, 8_int32, 8_int32, 13_int32], [3, 2]))
        r = mlx_take(a, idx)
        call expect(r, [3, 2], flat([1, 24, 3, 8, 8, 13]), &
            &'mlx_take(a, indices) takes 1-based positions in array element order and has the indices'' shape')
        wide = mlx_astype(idx, MLX_DTYPES%int64)
        r = mlx_take(a, wide)
        call expect(r, [3, 2], flat([1, 24, 3, 8, 8, 13]), 'mlx_take takes int64 positions')
        wide = mlx_astype(idx, MLX_DTYPES%uint64)
        r = mlx_take(a, wide)
        call expect(r, [3, 2], flat([1, 24, 3, 8, 8, 13]), 'mlx_take takes uint64 positions, shifted as signed integers')
        wide = mlx_astype(idx, MLX_DTYPES%uint8)
        r = mlx_take(a, wide)
        call expect(r, [3, 2], flat([1, 24, 3, 8, 8, 13]), 'mlx_take takes uint8 positions')
        idx = mlx_from(reshape([4_int32, 2_int32, 1_int32, 1_int32, 3_int32, 4_int32], [3, 2]))
        r = mlx_take(a, idx, 3)
        call expect(r, [N1, N2, 3, 2], [x(:, :, 4), x(:, :, 2), x(:, :, 1), x(:, :, 1), x(:, :, 3), x(:, :, 4)], &
            &'mlx_take(a, indices, 3) puts the indices'' (3, 2) shape in place of dimension 3')
        idx = mlx_from([4_int32, 2_int32])
        r = mlx_gather(a, idx, 3, [N1, N2, 1])
        call expect(r, [N1, N2, 1, 2], [x(:, :, 4), x(:, :, 2)], &
            &'mlx_gather(a, indices, 3, sizes): slabs a(:, :, k:k) at 1-based k, the indices'' shape last')
        idx = mlx_from([1_int32, 3_int32])
        r = mlx_gather(a, idx, 3, [N1, N2, 2])
        call expect(r, [N1, N2, 2, 2], [x(:, :, 1), x(:, :, 2), x(:, :, 3), x(:, :, 4)], &
            &'mlx_gather with a slice size of 2 takes a(:, :, k:k+1) for each k')
        idx = mlx_from([2_int32, 1_int32])
        jdx = mlx_from([3_int32, 2_int32])
        r = mlx_gather(a, [idx, jdx], [1, 2], [1, 1, N3])
        do p = 1, 2
            pair(1, 1, :, p) = x(merge(2, 1, p == 1), merge(3, 2, p == 1), :)
        end do
        call expect(r, [1, 1, N3, 2], reshape(pair, [2*N3]), &
            &'mlx_gather(a, [i, j], [1, 2], sizes) takes a(i(p):i(p), j(p):j(p), :) for each p')
        start = mlx_from([2_int32, 3_int32])
        r = mlx_slice(a, start, [2, 3], [N1, 2, 2])
        call expect(r, [N1, 2, 2], reshape(x(:, 2:3, 3:4), [N1*4]), &
            &'mlx_slice(a, start, dims, sizes) starts at 1-based positions held by an array of the graph')
        start = mlx_from([2_int32])
        r = mlx_slice(a, start, [1], [1, N2, N3])
        call expect(r, [1, N2, N3], reshape(x(2:2, :, :), [N2*N3]), 'mlx_slice(a, start, [1], sizes) starts along dimension 1')
    end subroutine test_take_and_gather

    ! mlx_scatter and its add, max, min and prod forms, with one and with two index arrays
    subroutine test_scatter
        type(mlx_array) :: a, idx, jdx, upd, r
        real(real32)    :: x(N1, N2, N3), want(N1, N2, N3), u(N1, N2, 1, 2), v(1, 1, N3, 2)
        write(*,'(a)') 'test_scatter'
        call fixture(x)
        a = mlx_from(x)
        u(:, :, 1, 1) = 1000._real32+x(:, :, 1)
        u(:, :, 1, 2) = x(:, :, 1)-2000._real32
        upd = mlx_from(u)
        idx = mlx_from([4_int32, 2_int32])
        r = mlx_scatter(a, idx, upd, 3)
        want = x
        want(:, :, 4) = u(:, :, 1, 1)
        want(:, :, 2) = u(:, :, 1, 2)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_scatter(a, indices, updates, 3) writes updates(:, :, 1, p) to a(:, :, indices(p))')
        idx = mlx_from([4_int32, 4_int32])
        r = mlx_scatter_add(a, idx, upd, 3)
        want = x
        want(:, :, 4) = x(:, :, 4)+u(:, :, 1, 1)+u(:, :, 1, 2)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_scatter_add accumulates the updates of a repeated position')
        idx = mlx_from([4_int32, 1_int32])
        r = mlx_scatter_max(a, idx, upd, 3)
        want = x
        want(:, :, 4) = max(x(:, :, 4), u(:, :, 1, 1))
        want(:, :, 1) = max(x(:, :, 1), u(:, :, 1, 2))
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_scatter_max keeps the larger of the element and its update: one slab replaced, one kept')
        r = mlx_scatter_min(a, idx, upd, 3)
        want = x
        want(:, :, 4) = min(x(:, :, 4), u(:, :, 1, 1))
        want(:, :, 1) = min(x(:, :, 1), u(:, :, 1, 2))
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_scatter_min keeps the smaller of the element and its update: the other slab replaced')
        u = 2._real32
        u(:, :, 1, 2) = 3._real32
        upd = mlx_from(u)
        r = mlx_scatter_prod(a, idx, upd, 3)
        want = x
        want(:, :, 4) = 2._real32*x(:, :, 4)
        want(:, :, 1) = 3._real32*x(:, :, 1)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_scatter_prod multiplies the element by its update')
        idx = mlx_from([2_int32, 1_int32])
        jdx = mlx_from([3_int32, 2_int32])
        v(1, 1, :, 1) = [1._real32, 2._real32, 3._real32, 4._real32]
        v(1, 1, :, 2) = [5000._real32, 6000._real32, 7000._real32, 8000._real32]
        upd = mlx_from(v)
        r = mlx_scatter(a, [idx, jdx], upd, [1, 2])
        want = x
        want(2, 3, :) = v(1, 1, :, 1)
        want(1, 2, :) = v(1, 1, :, 2)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_scatter(a, [i, j], updates, [1, 2]) writes updates(1, 1, :, p) to a(i(p), j(p), :)')
        r = mlx_scatter_add(a, [idx, jdx], upd, [1, 2])
        want = x
        want(2, 3, :) = x(2, 3, :)+v(1, 1, :, 1)
        want(1, 2, :) = x(1, 2, :)+v(1, 1, :, 2)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_scatter_add with two index arrays adds at (i(p), j(p), :)')
        r = mlx_scatter_max(a, [idx, jdx], upd, [1, 2])
        want = x
        want(1, 2, :) = v(1, 1, :, 2)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_scatter_max with two index arrays replaces a(i(2), j(2), :) by the larger updates and keeps a(i(1), j(1), :)')
        r = mlx_scatter_min(a, [idx, jdx], upd, [1, 2])
        want = x
        want(2, 3, :) = v(1, 1, :, 1)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_scatter_min with two index arrays replaces a(i(1), j(1), :) by the smaller updates and keeps a(i(2), j(2), :)')
        r = mlx_scatter_prod(a, [idx, jdx], upd, [1, 2])
        want = x
        want(2, 3, :) = x(2, 3, :)*v(1, 1, :, 1)
        want(1, 2, :) = x(1, 2, :)*v(1, 1, :, 2)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_scatter_prod with two index arrays multiplies at (i(p), j(p), :)')
    end subroutine test_scatter

    ! mlx_put_along_dim and the element-wise form of mlx_scatter_add, the inverses of mlx_take_along_dim
    subroutine test_along_dim
        type(mlx_array) :: a, idx, vals, r, back
        real(real32)    :: x(N1, N2, N3), want(N1, N2, N3), val(N1, 1, N3)
        integer(int32)  :: pos(N1, 1, N3)
        integer         :: i, k
        write(*,'(a)') 'test_along_dim'
        call fixture(x)
        a = mlx_from(x)
        want = x
        do k = 1, N3
            do i = 1, N1
                pos(i, 1, k) = int(mod(i+k, N2)+1, int32)
                val(i, 1, k) = real(-(i+10*k), real32)
                want(i, pos(i, 1, k), k) = val(i, 1, k)
            end do
        end do
        idx = mlx_from(pos)
        vals = mlx_from(val)
        r = mlx_put_along_dim(a, idx, vals, 2)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_put_along_dim(a, indices, values, 2) writes values(i, 1, k) to a(i, indices(i, 1, k), k)')
        back = mlx_take_along_dim(r, idx, 2)
        call expect(back, [N1, 1, N3], reshape(val, [N1*N3]), 'mlx_take_along_dim reads back what mlx_put_along_dim wrote')
        r = mlx_scatter_add(a, idx, vals, 2)
        do k = 1, N3
            do i = 1, N1
                want(i, pos(i, 1, k), k) = x(i, pos(i, 1, k), k)+val(i, 1, k)
            end do
        end do
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_scatter_add with indices of a''s rank adds values(i, 1, k) to a(i, indices(i, 1, k), k)')
    end subroutine test_along_dim

    ! mlx_slice_update and its add, max, min and prod forms; the dynamic form; mlx_masked_scatter
    subroutine test_section_updates
        type(mlx_array) :: a, upd, r, start, mask, src
        real(real32)    :: x(N1, N2, N3), want(N1, N2, N3), u(N1, 2, 2)
        logical(c_bool) :: m(N1, N2, N3)
        integer         :: i, j, k, n
        write(*,'(a)') 'test_section_updates'
        call fixture(x)
        a = mlx_from(x)
        do k = 1, 2
            do j = 1, 2
                do i = 1, N1
                    u(i, j, k) = real(200*k+20*j+i, real32)
                end do
            end do
        end do
        upd = mlx_from(u)
        r = mlx_slice_update(a, upd, [1, 2, 3], [N1, 3, 4])
        want = x
        want(:, 2:3, 3:4) = u
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_slice_update writes the section a(:, 2:3, 3:4), bounds as mlx_slice')
        r = mlx_slice_update(a, upd, [1, 1, 1], [N1, 3, 3], stride=[1, 2, 2])
        want = x
        want(:, 1:3:2, 1:3:2) = u
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_slice_update with strides writes a(:, 1:3:2, 1:3:2)')
        r = mlx_slice_update_add(a, upd, [1, 2, 3], [N1, 3, 4])
        want = x
        want(:, 2:3, 3:4) = x(:, 2:3, 3:4)+u
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_slice_update_add adds to the section')
        r = mlx_slice_update_max(a, upd, [1, 2, 3], [N1, 3, 4])
        want = x
        want(:, 2:3, 3:4) = max(x(:, 2:3, 3:4), u)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_slice_update_max keeps the larger in the section')
        r = mlx_slice_update_min(a, upd, [1, 2, 3], [N1, 3, 4])
        want = x
        want(:, 2:3, 3:4) = min(x(:, 2:3, 3:4), u)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), 'mlx_slice_update_min keeps the smaller in the section')
        upd = mlx_from(reshape([2._real32, 3._real32], [N1]))
        r = mlx_slice_update_prod(a, upd, [1, 2, 3], [N1, 3, 4])
        want = x
        want(1, 2:3, 3:4) = 2._real32*x(1, 2:3, 3:4)
        want(2, 2:3, 3:4) = 3._real32*x(2, 2:3, 3:4)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_slice_update_prod multiplies the section; an update of shape (n1) broadcasts along dimension 1')
        upd = mlx_from(u)
        start = mlx_from([2_int32, 3_int32])
        r = mlx_slice_update(a, upd, start, [2, 3])
        want = x
        want(:, 2:3, 3:4) = u
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_slice_update(a, update, start, dims) writes from 1-based positions held by an array of the graph')
        m = x > 250._real32 .and. mod(nint(x), 2) == 1
        n = count(m)
        mask = mlx_from(m)
        src = mlx_from([(real(-i, real32), i=1, n)])
        r = mlx_masked_scatter(a, mask, src)
        want = unpack([(real(-i, real32), i=1, n)], logical(m), x)
        call expect(r, [N1, N2, N3], reshape(want, [size(x)]), &
            &'mlx_masked_scatter fills the true elements, in array element order, with the elements of src')
    end subroutine test_section_updates

    ! mlx_searchsorted (positions 1 to n + 1, both sides) and mlx_unique (values, first positions, slots, counts)
    subroutine test_search_and_unique
        type(mlx_array)              :: s, v, r, a, fill
        type(mlx_array), allocatable :: res(:)
        real(real32)                 :: x(2, 4)
        logical                      :: ok
        write(*,'(a)') 'test_search_and_unique'
        s = mlx_from([1._real32, 2._real32, 2._real32, 3._real32])
        v = mlx_from([0._real32, 2._real32, 4._real32, 2.5_real32])
        r = mlx_searchsorted(s, v)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_searchsorted gives int32 positions')
        call expect(r, [4], [1._real32, 2._real32, 5._real32, 4._real32], &
            &'mlx_searchsorted gives 1-based positions from 1 to n + 1, before equal elements by default')
        r = mlx_searchsorted(s, v, side='right')
        call expect(r, [4], [1._real32, 4._real32, 5._real32, 4._real32], 'mlx_searchsorted(side=''right'') is after equal elements')
        v = mlx_from(reshape([2._real32, 0._real32, 3._real32, 9._real32], [2, 2]))
        r = mlx_searchsorted(s, v, side='left')
        call expect(r, [2, 2], [2._real32, 1._real32, 4._real32, 5._real32], 'mlx_searchsorted has the values'' shape')
        x = reshape([5._real32, 3._real32, 5._real32, 9._real32, 3._real32, 3._real32, 9._real32, 5._real32], [2, 4])
        a = mlx_from(x)
        call mlx_unique(a, 3, res)
        ok = size(res) == 4
        call assert_true(ok, 'mlx_unique returns values, first positions, slots and counts')
        if( ok )then
            call expect(res(1), [3], [3._real32, 5._real32, 9._real32], 'mlx_unique: results(1) is the distinct values, ascending')
            call expect(res(2), [3], [2._real32, 1._real32, 4._real32], &
                &'mlx_unique: results(2) is the 1-based position in array element order of each first occurrence')
            call assert_int(MLX_DTYPES%int32, res(2)%kind(), 'mlx_unique gives int32 positions')
            call expect(res(3), [2, 4], [2._real32, 1._real32, 2._real32, 3._real32, 1._real32, 1._real32, 3._real32, &
                &2._real32], 'mlx_unique: results(3) has a''s shape and holds the 1-based slot of each element')
            call expect(res(4), [3], [3._real32, 3._real32, 2._real32], 'mlx_unique: results(4) is the count of each value')
        endif
        fill = mlx_from(-1._real32)
        call mlx_unique(a, 5, res, fill=fill)
        ok = size(res) == 4
        call assert_true(ok, 'mlx_unique with more slots than values returns four results')
        if( ok )then
            call expect(res(1), [5], [3._real32, 5._real32, 9._real32, -1._real32, -1._real32], &
                &'mlx_unique pads the unused slots with fill')
            call expect(res(4), [5], [3._real32, 3._real32, 2._real32, 0._real32, 0._real32], 'mlx_unique counts zero in an unused slot')
        endif
    end subroutine test_search_and_unique

end module mlxf_ops_index_tester
