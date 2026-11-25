!@descr: two-device checks of the shape operations against Fortran's own array expressions
! The fixture is a (2, 3, 4) array whose element (i, j, k) holds i + 10 j + 100 k, so that every result names the
! elements it took: shapes and values are exact, and each assertion states the Fortran-order convention it checks.
module mlxf_ops_shape_tester
use, intrinsic :: iso_fortran_env, only: int32, real32
use mlxf,            only: mlx_array, mlx_from, mlx_to, mlx_set_default_device, mlx_default_device, MLX_DTYPES, &
                           mlx_astype, reshape, transpose, cshift, mlx_squeeze, mlx_expand_dims, mlx_flatten, &
                           mlx_unflatten, mlx_broadcast_to, mlx_broadcast_arrays, mlx_tile, mlx_repeat, mlx_pad, &
                           mlx_flip, mlx_movedim, mlx_swapdims, mlx_concatenate, mlx_stack, mlx_unstack, mlx_split, &
                           mlx_atleast_1d, mlx_atleast_2d, mlx_atleast_3d, mlx_diag, mlx_diagonal, mlx_trace, mlx_tril, &
                           mlx_triu, mlx_diff, mlx_as_strided, mlx_number_of_elements
use mlxf_test_utils, only: assert_true, assert_int, test_devices, device_name
implicit none
private
public :: run_all_ops_shape_tests

integer, parameter :: N1 = 2, N2 = 3, N3 = 4

contains

    subroutine run_all_ops_shape_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all ops_shape tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_rank_changes
            call test_repetition
            call test_reordering
            call test_lists
            call test_diagonals
            call test_strided_and_counts
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_ops_shape_tests

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

    ! the array's elements in array element order
    function flat3( x ) result(elements)
        real(real32), intent(in) :: x(:,:,:)
        real(real32) :: elements(size(x))
        elements = reshape(x, [size(x)])
    end function flat3

    function flat2( x ) result(elements)
        real(real32), intent(in) :: x(:,:)
        real(real32) :: elements(size(x))
        elements = reshape(x, [size(x)])
    end function flat2

    ! squeeze, expand_dims, flatten, unflatten, atleast_*, broadcast_to, broadcast_arrays
    subroutine test_rank_changes
        type(mlx_array)              :: a, b, r, v, s
        type(mlx_array), allocatable :: both(:)
        real(real32)                 :: x(N1, N2, N3), m(N1, N2)
        integer                      :: j
        write(*,'(a)') 'test_rank_changes'
        call fixture(x)
        a = mlx_from(x)
        m = x(:, :, 1)
        b = mlx_from(reshape(m, [N1, 1, N2, 1]))
        r = mlx_squeeze(b)
        call expect(r, [N1, N2], flat2(m), 'mlx_squeeze(a) drops every dimension of extent 1')
        r = mlx_squeeze(b, 2)
        call expect(r, [N1, N2, 1], flat2(m), 'mlx_squeeze(a, dim) drops Fortran dimension dim')
        r = mlx_squeeze(b, [4, 2])
        call expect(r, [N1, N2], flat2(m), 'mlx_squeeze(a, dims) drops the listed Fortran dimensions')
        r = mlx_expand_dims(a, 1)
        call expect(r, [1, N1, N2, N3], flat3(x), 'mlx_expand_dims(a, 1) adds a first dimension')
        r = mlx_expand_dims(a, 4)
        call expect(r, [N1, N2, N3, 1], flat3(x), 'mlx_expand_dims(a, rank + 1) adds a last dimension')
        r = mlx_expand_dims(a, 2)
        call expect(r, [N1, 1, N2, N3], flat3(x), 'mlx_expand_dims(a, 2) adds the dimension at position 2 of the result')
        r = mlx_expand_dims(a, [1, 5])
        call expect(r, [1, N1, N2, N3, 1], flat3(x), 'mlx_expand_dims(a, dims) names positions of the result')
        r = mlx_flatten(a)
        call expect(r, [N1*N2*N3], flat3(x), 'mlx_flatten(a) is the elements in array element order')
        r = mlx_flatten(a, 1, 2)
        call expect(r, [N1*N2, N3], flat3(x), 'mlx_flatten(a, 1, 2) merges dimensions 1 and 2, column-major')
        r = mlx_flatten(a, start_dim=2)
        call expect(r, [N1, N2*N3], flat3(x), 'mlx_flatten(a, start_dim=2) merges dimensions 2 to the last')
        b = mlx_from(reshape(x, [N1*N2, N3]))
        r = mlx_unflatten(b, 1, [N1, N2])
        call expect(r, [N1, N2, N3], flat3(x), 'mlx_unflatten(a, 1, shape) splits dimension 1 into a Fortran shape')
        b = mlx_from(reshape(x, [N1, N2*N3]))
        r = mlx_unflatten(b, 2, [N2, N3])
        call expect(r, [N1, N2, N3], flat3(x), 'mlx_unflatten(a, 2, shape) splits dimension 2 into a Fortran shape')
        s = mlx_from(7._real32)
        r = mlx_atleast_1d(s)
        call expect(r, [1], [7._real32], 'mlx_atleast_1d of a scalar has shape (1)')
        v = mlx_from(m(1, :))
        r = mlx_atleast_2d(v)
        call expect(r, [N2, 1], m(1, :), 'mlx_atleast_2d of shape (n) has shape (n, 1)')
        r = mlx_atleast_3d(v)
        call expect(r, [1, N2, 1], m(1, :), 'mlx_atleast_3d of shape (n) has shape (1, n, 1)')
        b = mlx_from(m)
        r = mlx_atleast_3d(b)
        call expect(r, [1, N1, N2], flat2(m), 'mlx_atleast_3d of shape (m, n) has shape (1, m, n)')
        r = mlx_atleast_3d(a)
        call expect(r, [N1, N2, N3], flat3(x), 'mlx_atleast_3d leaves a rank-3 array as it is')
        v = mlx_from(m(:, 1))
        r = mlx_broadcast_to(v, [N1, N2])
        call expect(r, [N1, N2], [(m(:, 1), j=1, N2)], 'mlx_broadcast_to aligns leading dimensions: r(i, j) = v(i)')
        b = mlx_from(reshape(m(1, :), [1, N2]))
        call mlx_broadcast_arrays([v, b], both)
        call assert_int(2, size(both), 'mlx_broadcast_arrays returns one array per input')
        call expect(both(1), [N1, N2], [(m(:, 1), j=1, N2)], 'mlx_broadcast_arrays: a (n) array varies along dimension 1')
        call expect(both(2), [N1, N2], flat2(spread(m(1, :), 1, N1)), &
            &'mlx_broadcast_arrays: a (1, n) array varies along dimension 2')
    end subroutine test_rank_changes

    ! tile, repeat, pad
    subroutine test_repetition
        type(mlx_array) :: b, r, fill, ints
        real(real32)    :: x(N1, N2, N3), m(N1, N2), want(N1+2, N2+2), wide(N1+1, N2+2)
        integer         :: i, j
        write(*,'(a)') 'test_repetition'
        call fixture(x)
        m = x(:, :, 1)
        b = mlx_from(m)
        r = mlx_tile(b, [2, 1])
        call expect(r, [2*N1, N2], flat2(reshape([((m(mod(i-1, N1)+1, j), i=1, 2*N1), j=1, N2)], [2*N1, N2])), &
            &'mlx_tile(a, [2, 1]) repeats the array twice along dimension 1')
        r = mlx_tile(b, [1, 2])
        call expect(r, [N1, 2*N2], [flat2(m), flat2(m)], 'mlx_tile(a, [1, 2]) repeats the array twice along dimension 2')
        r = mlx_tile(b, [2])
        call expect(r, [2*N1, N2], flat2(reshape([((m(mod(i-1, N1)+1, j), i=1, 2*N1), j=1, N2)], [2*N1, N2])), &
            &'mlx_tile with fewer repetitions than dimensions applies them to the first dimensions')
        r = mlx_repeat(b, 2, 1)
        call expect(r, [2*N1, N2], flat2(reshape([((m(shiftr(i+1, 1), j), i=1, 2*N1), j=1, N2)], [2*N1, N2])), &
            &'mlx_repeat(a, 2, 1) repeats every element twice along dimension 1')
        r = mlx_repeat(b, 2, 2)
        call expect(r, [N1, 2*N2], flat2(reshape([((m(i, shiftr(j+1, 1)), i=1, N1), j=1, 2*N2)], [N1, 2*N2])), &
            &'mlx_repeat(a, 2, 2) repeats every element twice along dimension 2')
        r = mlx_repeat(b, 2)
        call expect(r, [2*N1*N2], [((m(i, j), m(i, j), i=1, N1), j=1, N2)], &
            &'mlx_repeat(a, 2) repeats the elements in array element order, rank 1')
        want = 0._real32
        want(2:N1+1, 2:N2+1) = m
        r = mlx_pad(b, 1)
        call expect(r, [N1+2, N2+2], flat2(want), 'mlx_pad(a, 1) surrounds the array with one zero on every side')
        want = 7._real32
        want(2:N1+1, 2:N2+1) = m
        fill = mlx_from(7._real32)
        r = mlx_pad(b, 1, value=fill)
        call expect(r, [N1+2, N2+2], flat2(want), 'mlx_pad(a, 1, value) pads with the value')
        wide = 0._real32
        wide(2:N1+1, 1:N2) = m
        r = mlx_pad(b, [1, 0], [0, 2])
        call expect(r, [N1+1, N2+2], flat2(wide), &
            &'mlx_pad(a, low, high) pads per Fortran dimension: one before dimension 1, two after dimension 2')
        wide(1, 1:N2) = m(1, :)
        wide(:, N2+1) = wide(:, N2)
        wide(:, N2+2) = wide(:, N2)
        r = mlx_pad(b, [1, 0], [0, 2], mode='edge')
        call expect(r, [N1+1, N2+2], flat2(wide), 'mlx_pad(mode=''edge'') repeats the border elements')
        ints = mlx_astype(b, MLX_DTYPES%int32)
        r = mlx_pad(ints, 1)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_pad keeps an integer array''s kind with the default zero')
    end subroutine test_repetition

    ! flip, cshift, movedim, swapdims, transpose, diff
    subroutine test_reordering
        type(mlx_array) :: a, r, v
        real(real32)    :: x(N1, N2, N3)
        write(*,'(a)') 'test_reordering'
        call fixture(x)
        a = mlx_from(x)
        r = mlx_flip(a)
        call expect(r, [N1, N2, N3], flat3(x(N1:1:-1, N2:1:-1, N3:1:-1)), 'mlx_flip(a) reverses every dimension')
        r = mlx_flip(a, 1)
        call expect(r, [N1, N2, N3], flat3(x(N1:1:-1, :, :)), 'mlx_flip(a, 1) reverses Fortran dimension 1, MLX''s last axis')
        r = mlx_flip(a, [1])
        call expect(r, [N1, N2, N3], flat3(x(N1:1:-1, :, :)), 'mlx_flip(a, [1]) reverses Fortran dimension 1')
        r = mlx_flip(a, 2)
        call expect(r, [N1, N2, N3], flat3(x(:, N2:1:-1, :)), 'mlx_flip(a, 2) reverses Fortran dimension 2')
        r = mlx_flip(a, [1, 3])
        call expect(r, [N1, N2, N3], flat3(x(N1:1:-1, :, N3:1:-1)), 'mlx_flip(a, [1, 3]) reverses dimensions 1 and 3')
        v = mlx_from(x(1, 1, :))
        r = cshift(v, 1)
        call expect(r, [N3], cshift(x(1, 1, :), 1), 'cshift(v, 1) is Fortran''s: element i takes element i + 1')
        r = cshift(v, -1)
        call expect(r, [N3], cshift(x(1, 1, :), -1), 'cshift(v, -1) is Fortran''s')
        r = cshift(a, 1)
        call expect(r, [N1, N2, N3], flat3(cshift(x, 1, 1)), 'cshift(a, shift) shifts along dimension 1, as Fortran''s')
        r = cshift(a, -1, 2)
        call expect(r, [N1, N2, N3], flat3(cshift(x, -1, 2)), 'cshift(a, shift, 2) shifts along dimension 2, with Fortran''s sign')
        r = cshift(a, 5, 3)
        call expect(r, [N1, N2, N3], flat3(cshift(x, 5, 3)), 'cshift wraps a shift beyond the extent')
        r = cshift(a, [1, 2], [1, 3])
        call expect(r, [N1, N2, N3], flat3(cshift(cshift(x, 1, 1), 2, 3)), 'cshift(a, shifts, dims) shifts each listed dimension')
        r = mlx_movedim(a, 1, 3)
        call expect(r, [N2, N3, N1], flat3(reshape(x, [N2, N3, N1], order=[3, 1, 2])), &
            &'mlx_movedim(a, 1, 3) moves dimension 1 to the last position: r(j, k, i) = a(i, j, k)')
        r = mlx_movedim(a, 3, 1)
        call expect(r, [N3, N1, N2], flat3(reshape(x, [N3, N1, N2], order=[2, 3, 1])), &
            &'mlx_movedim(a, 3, 1) moves the last dimension first: r(k, i, j) = a(i, j, k)')
        r = mlx_swapdims(a, 1, 3)
        call expect(r, [N3, N2, N1], flat3(reshape(x, [N3, N2, N1], order=[3, 2, 1])), &
            &'mlx_swapdims(a, 1, 3) exchanges dimensions 1 and 3: r(k, j, i) = a(i, j, k)')
        r = mlx_swapdims(a, 1, 2)
        call expect(r, [N2, N1, N3], flat3(reshape(x, [N2, N1, N3], order=[2, 1, 3])), &
            &'mlx_swapdims(a, 1, 2) exchanges the first two Fortran dimensions: r(j, i, k) = a(i, j, k)')
        r = transpose(a)
        call expect(r, [N2, N1, N3], flat3(reshape(x, [N2, N1, N3], order=[2, 1, 3])), &
            &'transpose of a rank-3 array swaps dimensions 1 and 2 in every batch')
        v = mlx_from(x(:, :, 2))
        r = transpose(v)
        call expect(r, [N2, N1], flat2(transpose(x(:, :, 2))), 'transpose of a matrix is Fortran''s')
        r = mlx_diff(a)
        call expect(r, [N1-1, N2, N3], flat3(x(2:, :, :)-x(:N1-1, :, :)), 'mlx_diff(a) differences along dimension 1')
        r = mlx_diff(a, dim=2)
        call expect(r, [N1, N2-1, N3], flat3(x(:, 2:, :)-x(:, :N2-1, :)), 'mlx_diff(a, dim=2) is a(:, j + 1, :) - a(:, j, :)')
        r = mlx_diff(a*a, 2, 3)
        call expect(r, [N1, N2, N3-2], flat3(x(:, :, 3:)**2-2._real32*x(:, :, 2:N3-1)**2+x(:, :, :N3-2)**2), &
            &'mlx_diff(a, 2, 3) is the second difference along dimension 3')
    end subroutine test_reordering

    ! concatenate, stack, unstack, split
    subroutine test_lists
        type(mlx_array)              :: a, b, c, r
        type(mlx_array), allocatable :: parts(:)
        real(real32)                 :: x(N1, N2, N3), m(N1, N2), q(N1, N2), cat(2*N1, N2)
        integer                      :: k
        logical                      :: ok
        write(*,'(a)') 'test_lists'
        call fixture(x)
        a = mlx_from(x)
        m = x(:, :, 1)
        q = x(:, :, 2)
        b = mlx_from(m)
        c = mlx_from(q)
        r = mlx_concatenate([b, c])
        call expect(r, [2*N1*N2], [flat2(m), flat2(q)], &
            &'mlx_concatenate without a dimension joins the arrays'' elements in array element order, rank 1')
        r = mlx_concatenate([b, c], 2)
        call expect(r, [N1, 2*N2], [flat2(m), flat2(q)], 'mlx_concatenate(arrays, 2) joins along dimension 2')
        cat(:N1, :) = m
        cat(N1+1:, :) = q
        r = mlx_concatenate([b, c], 1)
        call expect(r, [2*N1, N2], flat2(cat), 'mlx_concatenate(arrays, 1) joins along dimension 1')
        r = mlx_stack([b, c])
        call expect(r, [N1, N2, 2], [flat2(m), flat2(q)], 'mlx_stack without a dimension adds a last dimension: r(:, :, n) = array n')
        r = mlx_stack([b, c], 1)
        call expect(r, [2, N1, N2], flat3(reshape([m, q], [2, N1, N2], order=[2, 3, 1])), &
            &'mlx_stack(arrays, 1) adds a first dimension: r(n, :, :) = array n')
        r = mlx_stack([b, c], 2)
        call expect(r, [N1, 2, N2], flat3(reshape([m, q], [N1, 2, N2], order=[1, 3, 2])), &
            &'mlx_stack(arrays, 2) adds the dimension at position 2: r(:, n, :) = array n')
        call mlx_unstack(a, parts)
        ok = size(parts) == N3
        call assert_true(ok, 'mlx_unstack(a) gives one array per element of the last dimension')
        if( ok )then
            do k = 1, N3
                call expect(parts(k), [N1, N2], flat2(x(:, :, k)), 'mlx_unstack(a): part k is a(:, :, k)')
            end do
        endif
        call mlx_unstack(a, parts, 1)
        ok = size(parts) == N1
        call assert_true(ok, 'mlx_unstack(a, parts, 1) gives one array per element of dimension 1')
        if( ok ) call expect(parts(2), [N2, N3], flat2(x(2, :, :)), 'mlx_unstack(a, parts, 1): part i is a(i, :, :)')
        call mlx_split(a, 2, parts)
        ok = size(parts) == 2
        call assert_true(ok, 'mlx_split(a, 2, parts) gives two parts')
        if( ok ) call expect(parts(2), [N1, N2, N3/2], flat3(x(:, :, N3/2+1:)), &
            &'mlx_split(a, 2, parts) cuts the last dimension in halves')
        call mlx_split(a, 3, parts, 2)
        ok = size(parts) == 3
        call assert_true(ok, 'mlx_split(a, 3, parts, 2) gives three parts')
        if( ok ) call expect(parts(3), [N1, 1, N3], flat3(x(:, 3:3, :)), 'mlx_split(a, 3, parts, 2) cuts dimension 2 in three')
        call mlx_split(a, [3], parts)
        ok = size(parts) == 2
        call assert_true(ok, 'mlx_split(a, [3], parts) cuts the last dimension once')
        if( ok ) call expect(parts(1), [N1, N2, 2], flat3(x(:, :, 1:2)), 'mlx_split(a, [3], parts): the first part is 1:2 of the last dimension')
        call mlx_split(a, [2], parts, 1)
        ok = size(parts) == 2
        call assert_true(ok, 'mlx_split(a, [2], parts, 1) cuts dimension 1 once')
        if( ok ) call expect(parts(2), [1, N2, N3], flat3(x(2:2, :, :)), 'mlx_split(a, [2], parts, 1): the second part is a(2:, :, :)')
        call mlx_split(a, [2, 4], parts, 3)
        ok = size(parts) == 3
        call assert_true(ok, 'mlx_split(a, [2, 4], parts, 3) gives three parts')
        if( ok )then
            call expect(parts(1), [N1, N2, 1], flat3(x(:, :, 1:1)), 'mlx_split at 1-based positions [2, 4]: the first part is 1:1')
            call expect(parts(2), [N1, N2, 2], flat3(x(:, :, 2:3)), 'mlx_split at 1-based positions [2, 4]: the second part is 2:3')
            call expect(parts(3), [N1, N2, 1], flat3(x(:, :, 4:4)), 'mlx_split at 1-based positions [2, 4]: the last part is 4:')
        endif
    end subroutine test_lists

    ! diag, diagonal, trace, tril, triu in the Fortran view: k > 0 is above the main diagonal, elements (i, i + k)
    subroutine test_diagonals
        type(mlx_array) :: a, b, r, v, k32
        real(real32)    :: x(N1, N2, N3), m(N2, N3), d(N2, N2), up(N2+1, N2+1), low(N2, N3), want(N2, N3)
        integer         :: i, j, k
        write(*,'(a)') 'test_diagonals'
        call fixture(x)
        a = mlx_from(x)
        m = x(1, :, :)
        b = mlx_from(m)
        v = mlx_from(m(:, 1))
        d = 0._real32
        up = 0._real32
        do i = 1, N2
            d(i, i) = m(i, 1)
            up(i, i+1) = m(i, 1)
        end do
        r = mlx_diag(v)
        call expect(r, [N2, N2], flat2(d), 'mlx_diag of a vector is the matrix with it on the main diagonal')
        r = mlx_diag(v, 1)
        call expect(r, [N2+1, N2+1], flat2(up), 'mlx_diag(v, 1) puts the vector above the main diagonal: r(i, i + 1) = v(i)')
        r = mlx_diag(v, -1)
        call expect(r, [N2+1, N2+1], flat2(transpose(up)), 'mlx_diag(v, -1) puts the vector below the main diagonal')
        r = mlx_diag(b)
        call expect(r, [N2], [(m(i, i), i=1, N2)], 'mlx_diag of a matrix is its main diagonal')
        r = mlx_diag(b, 1)
        call expect(r, [N2], [(m(i, i+1), i=1, N2)], 'mlx_diag(a, 1) is the diagonal above the main one: a(i, i + 1)')
        r = mlx_diag(b, -1)
        call expect(r, [N2-1], [(m(i+1, i), i=1, N2-1)], 'mlx_diag(a, -1) is the diagonal below the main one: a(i + 1, i)')
        r = mlx_diagonal(b, 1)
        call expect(r, [N2], [(m(i, i+1), i=1, N2)], 'mlx_diagonal(a, 1) of a matrix is a(i, i + 1)')
        r = mlx_diagonal(a)
        call expect(r, [N1, N3], [((x(i, i, k), i=1, N1), k=1, N3)], &
            &'mlx_diagonal(a) takes dimensions 1 and 2; the diagonal is dimension 1 of the result: r(i, k) = a(i, i, k)')
        r = mlx_diagonal(a, 1, 2, 3)
        call expect(r, [N2, N1], [((x(i, j, j+1), j=1, N2), i=1, N1)], &
            &'mlx_diagonal(a, 1, 2, 3): r(j, i) = a(i, j, j + 1)')
        r = mlx_diagonal(a, -1, 2, 3)
        call expect(r, [N2-1, N1], [((x(i, j+1, j), j=1, N2-1), i=1, N1)], &
            &'mlx_diagonal(a, -1, 2, 3): r(j, i) = a(i, j + 1, j)')
        r = mlx_trace(b)
        call expect(r, [integer ::], [sum([(m(i, i), i=1, N2)])], 'mlx_trace of a matrix is the sum of its main diagonal')
        r = mlx_trace(b, 1)
        call expect(r, [integer ::], [sum([(m(i, i+1), i=1, N2)])], 'mlx_trace(a, 1) sums a(i, i + 1)')
        r = mlx_trace(a)
        call expect(r, [N3], [(x(1, 1, k)+x(2, 2, k), k=1, N3)], 'mlx_trace(a) of a rank-3 array sums over dimensions 1 and 2')
        r = mlx_trace(a, 0, 2, 3)
        call expect(r, [N1], [(sum([(x(i, j, j), j=1, N2)]), i=1, N1)], 'mlx_trace(a, 0, 2, 3) sums a(i, j, j)')
        k32 = mlx_astype(b, MLX_DTYPES%int32)
        r = mlx_trace(k32, dtype=MLX_DTYPES%float32)
        call assert_int(MLX_DTYPES%float32, r%kind(), 'mlx_trace(dtype) gives the dtype asked for')
        r = mlx_trace(k32)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_trace keeps the array''s dtype by default')
        do k = -1, 1
            do j = 1, N3
                do i = 1, N2
                    low(i, j) = merge(m(i, j), 0._real32, j <= i+k)
                end do
            end do
            r = mlx_tril(b, k)
            call expect(r, [N2, N3], flat2(low), 'mlx_tril(a, k) keeps the Fortran elements (i, j) with j <= i + k')
            want = m-low
            do i = 1, N2
                if( i+k >= 1 .and. i+k <= N3 ) want(i, i+k) = m(i, i+k)
            end do
            r = mlx_triu(b, k)
            call expect(r, [N2, N3], flat2(want), 'mlx_triu(a, k) keeps the Fortran elements (i, j) with j >= i + k')
        end do
        r = mlx_tril(a)
        call expect(r, [N1, N2, N3], [(((merge(x(i, j, k), 0._real32, j <= i), i=1, N1), j=1, N2), k=1, N3)], &
            &'mlx_tril of a rank-3 array acts on dimensions 1 and 2 of every batch')
    end subroutine test_diagonals

    ! as_strided and number_of_elements
    subroutine test_strided_and_counts
        type(mlx_array) :: a, b, r, t
        real(real32)    :: x(N1, N2, N3), m(N2, N3), flat(N2*N3)
        integer         :: i, j
        write(*,'(a)') 'test_strided_and_counts'
        call fixture(x)
        a = mlx_from(x)
        m = x(1, :, :)
        flat = flat2(m)
        b = mlx_from(m)
        r = mlx_as_strided(b, [N2, N3], [1, N2])
        call expect(r, [N2, N3], flat, 'mlx_as_strided with the column-major strides (1, n1) is the array itself')
        r = mlx_as_strided(b, [2, 2], [1, N2], offset=1)
        call expect(r, [2, 2], [((flat(2+(i-1)+(j-1)*N2), i=1, 2), j=1, 2)], &
            &'mlx_as_strided: element (i, j) is element 1 + offset + (i - 1) s1 + (j - 1) s2 in array element order')
        r = mlx_as_strided(b, [N2], [-1], offset=N2-1)
        call expect(r, [N2], flat(N2:1:-1), 'mlx_as_strided with a negative stride walks back from its offset')
        r = mlx_as_strided(b, [N2*N3], [1])
        call expect(r, [N2*N3], flat, 'mlx_as_strided may reach the last element of a')
        r = mlx_as_strided(b, [0, N3], [1, 10*N2*N3], offset=5*N2*N3)
        call assert_int(0, int(r%size()), 'mlx_as_strided: an empty view reaches no element, whatever its strides and offset')
        r = mlx_as_strided(b, [N3, N2], [N2, 1])
        call expect(r, [N3, N2], flat2(transpose(m)), 'mlx_as_strided with exchanged strides is the transpose')
        t = transpose(b)
        r = mlx_as_strided(t, [N3, N2], [1, N3])
        call expect(r, [N3, N2], flat2(transpose(m)), 'mlx_as_strided of a strided array strides over its elements, not its buffer')
        r = mlx_number_of_elements(a)
        call expect(r, [integer ::], [real(N1*N2*N3, real32)], 'mlx_number_of_elements(a) is the size, rank 0')
        call assert_int(MLX_DTYPES%float32, r%kind(), 'mlx_number_of_elements is float32 by default')
        r = mlx_number_of_elements(a, [1, 3])
        call expect(r, [integer ::], [real(N1*N3, real32)], 'mlx_number_of_elements(a, dims) multiplies the extents of Fortran dimensions')
        r = mlx_number_of_elements(a, [1])
        call expect(r, [integer ::], [real(N1, real32)], 'mlx_number_of_elements(a, [1]) is the extent of Fortran dimension 1')
        r = mlx_number_of_elements(a, [1, 3], inverted=.true.)
        call expect(r, [integer ::], [1._real32/real(N1*N3, real32)], 'mlx_number_of_elements(inverted) is the reciprocal')
        r = mlx_number_of_elements(a, dtype=MLX_DTYPES%int32)
        call assert_int(MLX_DTYPES%int32, r%kind(), 'mlx_number_of_elements(dtype) gives the dtype asked for')
    end subroutine test_strided_and_counts

end module mlxf_ops_shape_tester
