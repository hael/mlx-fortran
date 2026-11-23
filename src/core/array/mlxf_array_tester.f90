!@descr: tests of mlxf_array: the leak gate, byte identity of data movement, memory order, views, the zero-copy table
module mlxf_array_tester
use, intrinsic :: iso_c_binding, only: c_bool, c_int, c_f_pointer
use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
use mlxf_c_array,    only: mlxc_array_ndim, mlxc_array_shape
use mlxf_c_ops,      only: mlxc_transpose
use mlxf,            only: mlx_array, mlx_function, mlx_compile, MLX_DEVICES, MLX_DTYPES, mlx_from, mlx_to, &
                           mlx_to_alloc, mlx_view, mlx_alloc, mlx_eval, mlx_synchronize, mlx_clear_cache, &
                           mlx_active_memory, mlx_live_count, mlx_is_live, mlx_last_error, mlx_default_device, &
                           mlx_set_default_device, exp, sum, sqrt, reshape, transpose, matmul, mlx_rfft, mlx_irfft
use mlxf_registry,   only: registry_stale_releases
use mlxf_array,      only: mlxf_handle, mlxf_unary
use mlxf_test_utils, only: assert_true, assert_int, bits_equal, test_devices, device_name, set_fixed_seed
implicit none
private

public :: run_all_array_tests

integer, parameter :: NITER = 10000

! a derived type with plain handle components: intrinsic assignment calls their defined assignment
type :: plain_holder
    type(mlx_array) :: s
    type(mlx_array) :: arr(2)
end type plain_holder

! a derived type with allocatable handle components: its own assignment copies them element by element
! (gfortran skips the components' defined assignment in intrinsic assignment)
type :: alloc_holder
    type(mlx_array), allocatable :: s
    type(mlx_array), allocatable :: arr(:)
  contains
    procedure, private :: alloc_holder_assign
    generic            :: assignment(=) => alloc_holder_assign
end type alloc_holder

contains

    subroutine run_all_array_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(A)') '**** running all array tests ****'
        call test_devices(devs)
        if( size(devs) == 0 ) return
        original = mlx_default_device()
        do i = 1, size(devs)
            write(*,'(A)') '  on the '//device_name(devs(i))
            call mlx_set_default_device(devs(i))
            call test_identity_real32(devs(i))
            call test_identity_kinds(devs(i))
            call test_sections_and_empty
            call test_memory_order
            call test_view_survives
            call test_checked_failures
            call test_leak_gate(devs(i))
            call test_operation_leaks
            call test_compiled_leak
        end do
        call mlx_set_default_device(original)
        call test_zero_copy_table
    end subroutine run_all_array_tests

    ! ---- the leak gate -------------------------------------------------------------------------------------

    impure elemental subroutine alloc_holder_assign( lhs, rhs )
        class(alloc_holder), intent(inout) :: lhs
        class(alloc_holder), intent(in)    :: rhs
        integer :: i
        if( allocated(rhs%s) )then
            if( .not. allocated(lhs%s) ) allocate(lhs%s)
            lhs%s = rhs%s
        else if( allocated(lhs%s) )then
            deallocate(lhs%s)
        endif
        if( allocated(lhs%arr) .and. allocated(rhs%arr) )then
            if( size(lhs%arr) /= size(rhs%arr) ) deallocate(lhs%arr)
        endif
        if( allocated(rhs%arr) )then
            if( .not. allocated(lhs%arr) ) allocate(lhs%arr(size(rhs%arr)))
            do i = 1, size(rhs%arr)
                lhs%arr(i) = rhs%arr(i)
            end do
        else if( allocated(lhs%arr) )then
            deallocate(lhs%arr)
        endif
    end subroutine alloc_holder_assign

    subroutine take_one( x )
        type(mlx_array), intent(in) :: x
        type(mlx_array) :: y
        y = x * x
    end subroutine take_one

    subroutine take_list( xs )
        type(mlx_array), intent(in) :: xs(:)
        type(mlx_array) :: y
        y = xs(1) + xs(size(xs))
    end subroutine take_list

    subroutine make( x, a, b )
        type(mlx_array), intent(out) :: x
        type(mlx_array), intent(in)  :: a, b
        x = a - b
    end subroutine make

    subroutine scoped( a, b )
        type(mlx_array), intent(in) :: a, b
        type(mlx_array) :: loc, arr(2)
        loc    = a + b
        arr(1) = loc
        arr(2) = exp(b)
    end subroutine scoped

    ! one iteration: every supported form of the handle model
    subroutine leak_body( a, b )
        type(mlx_array), intent(in) :: a, b
        type(mlx_array)              :: c, d, e, pair(2)
        type(mlx_array), allocatable :: v(:), w(:,:,:)
        type(plain_holder)           :: p1, p2
        type(alloc_holder)           :: q1, q2
        integer                      :: i, j, k
        c = exp(a*2.0 + b)
        call mlx_eval(c)
        c = c
        d = (a)
        call take_list([c, d])
        pair(1) = c
        pair(2) = d
        call mlx_eval(pair)
        call take_one(exp(a))
        call take_one(a + b)
        call make(e, a, b)
        call make(e, b, a)
        allocate(v(3), w(2, 2, 2))
        do i = 1, size(v)
            v(i) = a
        end do
        v(2) = exp(b)
        do k = 1, 2
            do j = 1, 2
                do i = 1, 2
                    w(i, j, k) = b
                end do
            end do
        end do
        w(2, 1, 2) = c + d
        w = c
        v(3) = v(1)
        deallocate(v, w)
        p1%s      = a
        p1%arr(1) = b
        p1%arr(2) = c
        p2 = p1
        p2%arr(1) = d
        allocate(q1%s, q1%arr(2))
        q1%s      = a
        q1%arr(1) = b
        q1%arr(2) = c
        q2 = q1
        q2 = q1
        call scoped(a, b)
    end subroutine leak_body

    ! the leak gate: after a warm-up, with synchronize and clear_cache before both reads, the active memory,
    ! the live count and the stale releases after NITER iterations equal their values before
    subroutine test_leak_gate( dev )
        integer, intent(in) :: dev
        real(real32)    :: x(4, 3), z(4, 3)
        type(mlx_array) :: a, b
        integer(int64)  :: mem0, t0, t1, rate
        integer         :: it, live0, stale0
        write(*,'(A)') 'test_leak_gate'
        x = 0.25_real32
        z = 0.5_real32
        a = mlx_from(x)
        b = mlx_from(z)
        call leak_body(a, b)
        call mlx_synchronize()
        call mlx_clear_cache()
        mem0   = mlx_active_memory()
        live0  = mlx_live_count()
        stale0 = registry_stale_releases()
        call system_clock(t0, rate)
        do it = 1, NITER
            call leak_body(a, b)
        end do
        call system_clock(t1)
        write(*,'(A,I0,A,F7.2,A)') '    ', NITER, ' iterations in ', real(t1 - t0) / real(rate), ' s'
        call mlx_synchronize()
        call mlx_clear_cache()
        call assert_true(mlx_active_memory() == mem0, device_name(dev)//': the active memory after the loop equals '//&
            &'the memory before')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': the live count after the loop equals the count before')
        call assert_int(stale0, registry_stale_releases(), device_name(dev)//': no stale release in the loop')
    end subroutine test_leak_gate

    ! ---- byte identity -------------------------------------------------------------------------------------

    ! n float32 of arbitrary bit patterns (NaN payloads and signed zeros included), from the seeded generator
    function random_r32( n ) result(x)
        integer, intent(in) :: n
        real(real32) :: x(n)
        real(real64) :: r(n)
        call random_number(r)
        x = transfer(int(r * 4294967295._real64 - 2147483648._real64, int32), x)
    end function random_r32

    function random_i64( n ) result(k)
        integer, intent(in) :: n
        integer(int64) :: k(n)
        real(real64)   :: r(n)
        call random_number(r)
        k = ieor(ishft(int(r * 2._real64**31, int64), 33), int(r * 2._real64**52, int64))
    end function random_i64

    ! float32 at ranks 0 to 4 and 7: mlx_from, then mlx_to and mlx_to_alloc give back every byte
    subroutine test_identity_real32( dev )
        integer, intent(in) :: dev
        real(real32)              :: x0, y0, flat(36)
        real(real32), allocatable :: x1(:), y1(:), x2(:,:), y2(:,:), x3(:,:,:), y3(:,:,:), x4(:,:,:,:), y4(:,:,:,:)
        real(real32), allocatable :: x7(:,:,:,:,:,:,:), y7(:,:,:,:,:,:,:)
        type(mlx_array)           :: a
        integer(int64)            :: n
        integer                   :: st, st2, nd
        write(*,'(A)') 'test_identity_real32'
        call set_fixed_seed(11)
        flat = random_r32(36)
        x0 = flat(1)
        a  = mlx_from(x0)
        call mlx_to(y0, a, status=st)
        nd = a%ndim()
        call assert_true(st == 0 .and. bits_equal(x0, y0) .and. nd == 0, &
            &device_name(dev)//': float32 rank 0 round-trips byte for byte')
        x1 = flat(1:7)
        a  = mlx_from(x1)
        allocate(y1(7))
        call mlx_to(y1, a, status=st)
        call assert_true(st == 0 .and. all(bits_equal(x1, y1)), device_name(dev)//': float32 rank 1 via mlx_to')
        deallocate(y1)
        call mlx_to_alloc(y1, a, status=st2)
        call assert_true(st2 == 0 .and. all(bits_equal(x1, y1)), device_name(dev)//': float32 rank 1 via mlx_to_alloc')
        x2 = reshape(flat(1:15), [3, 5])
        a  = mlx_from(x2)
        call mlx_to_alloc(y2, a, status=st)
        call assert_true(st == 0 .and. all(shape(y2) == [3, 5]) .and. all(bits_equal(x2, y2)), &
            &device_name(dev)//': float32 rank 2 (3,5) round-trips')
        x3 = reshape(flat(1:30), [3, 2, 5])
        a  = mlx_from(x3)
        call mlx_to_alloc(y3, a, status=st)
        call assert_true(st == 0 .and. all(shape(y3) == [3, 2, 5]) .and. all(bits_equal(x3, y3)), &
            &device_name(dev)//': float32 rank 3 (3,2,5) round-trips')
        x4 = reshape(flat(1:30), [2, 3, 1, 5])
        a  = mlx_from(x4)
        call mlx_to_alloc(y4, a, status=st)
        call assert_true(st == 0 .and. all(shape(y4) == [2, 3, 1, 5]) .and. all(bits_equal(x4, y4)), &
            &device_name(dev)//': float32 rank 4 (2,3,1,5) round-trips')
        x7 = reshape(flat(1:36), [2, 1, 3, 1, 2, 1, 3])
        a  = mlx_from(x7)
        call mlx_to_alloc(y7, a, status=st)
        call assert_true(st == 0 .and. all(shape(y7) == [2, 1, 3, 1, 2, 1, 3]) .and. all(bits_equal(x7, y7)), &
            &device_name(dev)//': float32 rank 7 (2,1,3,1,2,1,3) round-trips')
        nd = a%kind()
        n  = a%size()
        call assert_true(nd == MLX_DTYPES%float32 .and. n == 36_int64, &
            &device_name(dev)//': a float32 array reports its kind and size')
    end subroutine test_identity_real32

    ! the other five kinds at ranks 0, 2 (3,5) and 3 (3,2,5); float64 on the CPU device only
    subroutine test_identity_kinds( dev )
        integer, intent(in) :: dev
        integer(int64)               :: bits(30)
        real(real64)                 :: d0, e0
        real(real64)                 :: d2(3, 5), d3(3, 2, 5)
        real(real64),    allocatable :: e2(:,:), e3(:,:,:)
        complex(real32)              :: c0, f0
        complex(real32)              :: c2(3, 5), c3(3, 2, 5)
        complex(real32), allocatable :: f2(:,:), f3(:,:,:)
        integer(int32)               :: i0, j0
        integer(int32)               :: i2(3, 5), i3(3, 2, 5)
        integer(int32),  allocatable :: j2(:,:), j3(:,:,:)
        integer(int64)               :: k0, l0
        integer(int64)               :: k2(3, 5), k3(3, 2, 5)
        integer(int64),  allocatable :: l2(:,:), l3(:,:,:)
        logical(c_bool)              :: b0, g0
        logical(c_bool)              :: b2(3, 5), b3(3, 2, 5)
        logical(c_bool), allocatable :: g2(:,:), g3(:,:,:)
        type(mlx_array)              :: a
        integer                      :: st, s2, s3, dkind
        write(*,'(A)') 'test_identity_kinds'
        call set_fixed_seed(12)
        bits = random_i64(30)
        if( dev == MLX_DEVICES%cpu )then
            d0 = transfer(bits(1), d0)
            a  = mlx_from(d0)
            call mlx_to(e0, a, status=st)
            d2 = reshape(transfer(bits(1:15), 1._real64, 15), [3, 5])
            a  = mlx_from(d2)
            call mlx_to_alloc(e2, a, status=s2)
            d3 = reshape(transfer(bits(1:30), 1._real64, 30), [3, 2, 5])
            a  = mlx_from(d3)
            call mlx_to_alloc(e3, a, status=s3)
        dkind = a%kind()
            call assert_true(st == 0 .and. s2 == 0 .and. s3 == 0 .and. bits_equal(d0, e0) .and. &
                &all(bits_equal(d2, e2)) .and. all(bits_equal(d3, e3)) .and. dkind == MLX_DTYPES%float64, &
                &device_name(dev)//': float64 ranks 0, 2, 3 round-trip byte for byte')
        endif
        c0 = transfer(bits(2), c0)
        a  = mlx_from(c0)
        call mlx_to(f0, a, status=st)
        c2 = reshape(transfer(bits(1:15), (1._real32, 0._real32), 15), [3, 5])
        a  = mlx_from(c2)
        call mlx_to_alloc(f2, a, status=s2)
        c3 = reshape(transfer(bits(1:30), (1._real32, 0._real32), 30), [3, 2, 5])
        a  = mlx_from(c3)
        call mlx_to_alloc(f3, a, status=s3)
        dkind = a%kind()
        call assert_true(st == 0 .and. s2 == 0 .and. s3 == 0 .and. bits_equal(c0, f0) .and. &
            &all(bits_equal(c2, f2)) .and. all(bits_equal(c3, f3)) .and. dkind == MLX_DTYPES%complex64, &
            &device_name(dev)//': complex64 ranks 0, 2, 3 round-trip byte for byte')
        i0 = int(ibits(bits(3), 0, 31), int32)
        a  = mlx_from(i0)
        call mlx_to(j0, a, status=st)
        i2 = reshape(int(ibits(bits(1:15), 0, 31), int32), [3, 5])
        a  = mlx_from(i2)
        call mlx_to_alloc(j2, a, status=s2)
        i3 = reshape(int(ibits(bits(1:30), 0, 31), int32), [3, 2, 5])
        a  = mlx_from(i3)
        call mlx_to_alloc(j3, a, status=s3)
        dkind = a%kind()
        call assert_true(st == 0 .and. s2 == 0 .and. s3 == 0 .and. i0 == j0 .and. all(i2 == j2) .and. &
            &all(i3 == j3) .and. dkind == MLX_DTYPES%int32, device_name(dev)//': int32 ranks 0, 2, 3 round-trip')
        k0 = bits(4)
        a  = mlx_from(k0)
        call mlx_to(l0, a, status=st)
        k2 = reshape(bits(1:15), [3, 5])
        a  = mlx_from(k2)
        call mlx_to_alloc(l2, a, status=s2)
        k3 = reshape(bits(1:30), [3, 2, 5])
        a  = mlx_from(k3)
        call mlx_to_alloc(l3, a, status=s3)
        dkind = a%kind()
        call assert_true(st == 0 .and. s2 == 0 .and. s3 == 0 .and. k0 == l0 .and. all(k2 == l2) .and. &
            &all(k3 == l3) .and. dkind == MLX_DTYPES%int64, device_name(dev)//': int64 ranks 0, 2, 3 round-trip')
        b0 = .true.
        a  = mlx_from(b0)
        call mlx_to(g0, a, status=st)
        b2 = reshape(logical(btest(bits(1:15), 7), c_bool), [3, 5])
        a  = mlx_from(b2)
        call mlx_to_alloc(g2, a, status=s2)
        b3 = reshape(logical(btest(bits(1:30), 9), c_bool), [3, 2, 5])
        a  = mlx_from(b3)
        call mlx_to_alloc(g3, a, status=s3)
        dkind = a%kind()
        call assert_true(st == 0 .and. s2 == 0 .and. s3 == 0 .and. (b0 .eqv. g0) .and. all(b2 .eqv. g2) .and. &
            &all(b3 .eqv. g3) .and. dkind == MLX_DTYPES%bool, device_name(dev)//': bool ranks 0, 2, 3 round-trip')
    end subroutine test_identity_kinds

    ! strided sections in and out (the compiler copies in and out of the contiguous dummies), odd sizes, a
    ! zero-size array, and a never-assigned mlx_array assigned over a live one
    subroutine test_sections_and_empty
        real(real32)              :: x(7, 6), y(10, 6), empty(0)
        real(real32), allocatable :: z(:)
        type(mlx_array)           :: a, unset
        integer(int64)            :: n
        integer, allocatable      :: shp(:)
        integer                   :: st, live, now
        logical                   :: held
        write(*,'(A)') 'test_sections_and_empty'
        call set_fixed_seed(13)
        x = reshape(random_r32(42), [7, 6])
        y = 0._real32
        a = mlx_from(x(1:7:2, 2:6))
        call assert_true(all(a%shape() == [4, 5]), 'a strided section reaches MLX with its own shape')
        call mlx_to(y(1:10:3, 2:6), a, status=st)
        call assert_true(st == 0 .and. all(bits_equal(y(1:10:3, 2:6), x(1:7:2, 2:6))), &
            &'a strided section in and a strided section out keep every byte')
        call assert_true(all(bits_equal(y(2:10:3, :), 0._real32)) .and. all(bits_equal(y(:, 1), 0._real32)), &
            &'elements outside the output section are untouched')
        a = mlx_from(empty)
        n   = a%size()
        shp = a%shape()
        call assert_true(n == 0_int64 .and. all(shp == [0]), 'a zero-size array is an empty MLX array')
        call mlx_to_alloc(z, a, status=st)
        call assert_true(st == 0 .and. size(z) == 0, 'a zero-size array comes back with size 0')
        live = mlx_live_count()
        a    = unset
        held = mlx_is_live(a)
        now  = mlx_live_count()
        call assert_true(.not. held .and. now == live-1, &
            &'a never-assigned mlx_array assigned over a live one frees its object and leaves it empty')
    end subroutine test_sections_and_empty

    ! (3,5) reaches MLX as [5,3]; a transposed view holds the transpose and is no view of Fortran order; mlx_to
    ! copies it into its own shape or a vector of its size, never into another shape of that size
    subroutine test_memory_order
        real(real32)              :: x(3, 5), y(5, 3), yy(3, 5), flat(15)
        real(real32), pointer     :: p(:,:)
        type(mlx_array)           :: a, t
        integer(c_int), pointer   :: cs(:)
        integer                   :: st, i, j
        write(*,'(A)') 'test_memory_order'
        do j = 1, 5
            do i = 1, 3
                x(i, j) = real(10 * i + j, real32)
            end do
        end do
        a = mlx_from(x)
        call c_f_pointer(mlxc_array_shape(mlxf_handle(a, 'test')), cs, [2])
        call assert_true(mlxc_array_ndim(mlxf_handle(a, 'test')) == 2 .and. all(cs == [5, 3]), &
            &'a Fortran (3,5) array reaches MLX as shape [5,3] over the same bytes')
        call assert_true(all(a%shape() == [3, 5]), 'a%shape() returns the Fortran shape [3,5]')
        call mlxf_unary(t, mlxc_transpose, a, 'test')
        call assert_true(all(t%shape() == [5, 3]), 'the transpose has the Fortran shape [5,3]')
        call mlx_to(y, t, status=st)
        call assert_true(st == 0 .and. all(bits_equal(y, transpose(x))), &
            &'copying out the transposed view gives Fortran''s transpose')
        yy = 0._real32
        call mlx_to(yy, t, status=st)
        call assert_true(st /= 0 .and. all(bits_equal(yy, 0._real32)), &
            &'a (3,5) destination for the (5,3) transpose is refused and left untouched')
        call assert_true(index(mlx_last_error(), 'differ in shape') > 0, 'and the message says the shapes differ')
        call mlx_to(flat, t, status=st)
        call assert_true(st == 0 .and. all(bits_equal(flat, reshape(transpose(x), [15]))), &
            &'a rank-1 destination of the same size takes the transpose in Fortran element order')
        nullify(p)
        call mlx_view(t, p, status=st)
        call assert_true(st /= 0 .and. .not. associated(p), 'mlx_view of a non-contiguous array returns a status')
        call assert_true(index(mlx_last_error(), 'not contiguous') > 0, 'and the message says it is not contiguous')
    end subroutine test_memory_order

    ! a view of an evaluated array survives unrelated evaluations
    subroutine test_view_survives
        real(real32)          :: x(3, 5), z(16)
        real(real32), pointer :: p(:,:)
        type(mlx_array)       :: a, b, o
        integer               :: st, k
        logical               :: ok
        write(*,'(A)') 'test_view_survives'
        call set_fixed_seed(14)
        x = reshape(random_r32(15), [3, 5])
        z = 0.5_real32
        a = mlx_from(x)
        b = mlx_from(z)
        call mlx_view(a, p, status=st)
        call assert_true(st == 0 .and. associated(p), 'an evaluated row-contiguous array can be viewed')
        if( .not. associated(p) ) return
        call assert_true(all(shape(p) == [3, 5]) .and. all(bits_equal(p, x)), 'the view shows the array in Fortran order')
        ok = .true.
        do k = 1, 20
            o = exp(b*2.0) + b
            call mlx_eval(o)
            ok = ok .and. all(bits_equal(p, x))
        end do
        call assert_true(ok, 'the view survives twenty unrelated evaluations')
    end subroutine test_view_survives

    ! the failures of the checked procedures return a status and leave the pointer disassociated
    subroutine test_checked_failures
        real(real32),     target      :: x(3, 5), empty(0), x8(1, 1, 1, 1, 1, 1, 1, 1)
        real(real32),     pointer     :: p2(:,:), p1(:), p3(:,:,:), p8(:,:,:,:,:,:,:,:)
        real(real32),     allocatable :: col(:,:), row(:,:), big(:,:)
        character(len=:), allocatable :: msg
        type(mlx_array)               :: a, ca, cb
        integer                       :: st
        write(*,'(A)') 'test_checked_failures'
        x  = 1.0_real32
        x8 = 1.0_real32
        p2 => x
        a  = mlx_alloc([3, 5], 1.0_real32, p1, status=st)
        call assert_true(st /= 0 .and. .not. associated(p1), &
            &'mlx_alloc with a view whose rank differs from the shape returns a status and no view')
        ! the byte count at the edge of what a size holds: one side is refused before any allocation, the
        ! other is representable and fails in the allocator; neither returns a view
        p3 => null()
        a  = mlx_alloc([2**30, 2**29, 7], 1.0_real32, p3, status=st)
        msg = mlx_last_error()
        call assert_true(st /= 0 .and. .not. associated(p3) .and. index(msg, 'not representable') > 0, &
            &'mlx_alloc refuses a shape whose size in bytes does not fit before allocating')
        a  = mlx_alloc([2**30, 2**29, 3], 1.0_real32, p3, status=st)
        msg = mlx_last_error()
        call assert_true(st /= 0 .and. .not. associated(p3) .and. index(msg, 'posix_memalign') > 0, &
            &'mlx_alloc of a representable size no host holds returns the allocator''s failure')
        a  = mlx_alloc([3, 5, 2], 1.0_real32, p3, status=st)
        call assert_true(st == 0 .and. associated(p3), 'mlx_alloc of an ordinary shape still succeeds')
        ! a pointer of a rank above 7, associated before the call, is null after any refusal
        p8 => x8
        a  = mlx_alloc([1, 1, 1, 1, 1, 1, 1, 1], 1.0_real32, p8, status=st)
        call assert_true(st /= 0 .and. .not. associated(p8), &
            &'mlx_alloc refuses a rank above 7 and disassociates the pointer')
        a = mlx_from(empty)
        call mlx_view(a, p1, status=st)
        call assert_true(st /= 0 .and. .not. associated(p1), 'mlx_view of an array without elements returns a status')
        a = mlx_from(x)
        p8 => x8
        call mlx_view(a, p8, status=st)
        call assert_true(st /= 0 .and. .not. associated(p8), &
            &'mlx_view with a pointer of a rank above 7 returns a status and disassociates the pointer')
        p1 => x(:, 1)
        call mlx_view(a, p1, status=st)
        call assert_true(st /= 0 .and. .not. associated(p1), &
            &'mlx_view with a pointer of the wrong rank returns a status and disassociates the pointer')
        call mlx_view(a, p2, status=st)
        call assert_true(st == 0 .and. associated(p2), 'the same array viewed at its own rank succeeds')
        ! a destination no host can allocate: a lazy broadcast of 2**48 float32 (1 PiB), never evaluated
        allocate(col(2**24, 1), row(1, 2**24), source=0.0_real32)
        ca = mlx_from(col)
        cb = mlx_from(row)
        a  = ca + cb
        call mlx_to_alloc(big, a, status=st)
        msg = mlx_last_error()
        call assert_true(st /= 0 .and. .not. allocated(big) .and. index(msg, 'could not be allocated') > 0, &
            &'mlx_to_alloc to a destination that cannot be allocated returns a status and a message')
    end subroutine test_checked_failures

    ! which mlx_alloc sizes Metal takes without a copy (printed), and that the data written through the view
    ! is the array's either way
    subroutine test_zero_copy_table
        integer, parameter :: NSIZES = 11
        integer, parameter :: BYTES(NSIZES) = [1024, 4096, 16384, 20480, 49152, 100000, 1048576, 1052672, 16777216, &
            &67104768, 67108864]
        real(real32), pointer     :: view(:)
        real(real32), allocatable :: y(:)
        type(mlx_array)           :: a
        integer                   :: k, i, n, st
        logical                   :: zc, ok
        write(*,'(A)') 'test_zero_copy_table'
        write(*,'(A)') '    bytes      multiple_of_16KiB  zero_copy'
        do k = 1, NSIZES
            n = BYTES(k) / 4
            a = mlx_alloc([n], 1.0_real32, view, status=st, zero_copy=zc)
            ok = st == 0 .and. associated(view)
            if( ok )then
                do i = 1, n
                    view(i) = real(i, real32)
                end do
                call mlx_to_alloc(y, a, status=st)
                ok = st == 0 .and. size(y) == n
                if( ok ) ok = all(bits_equal(y, view))
            endif
            write(*,'(4X,I10,1X,L18,1X,L10)') BYTES(k), mod(BYTES(k), 16384) == 0, zc
            call assert_true(ok, 'the data written through the view of mlx_alloc is the array''s')
            call a%kill()
        end do
    end subroutine test_zero_copy_table

    ! the operation modules' expressions (reductions, matmul, FFTs), evaluated 10,000 times per device,
    ! leave the live count and active memory where they were
    subroutine test_operation_leaks
        type(mlx_array) :: a
        real(real32)    :: x(4, 3)
        integer         :: family, it, live0, stale0
        integer(int64)  :: mem0
        write(*,'(a)') 'test_operation_leaks'
        x = 0.25_real32
        a = mlx_from(x)
        do family = 1, 3
            call operation_leak_body(a, family)
            call mlx_synchronize()
            call mlx_clear_cache()
            mem0 = mlx_active_memory()
            live0 = mlx_live_count()
            stale0 = registry_stale_releases()
            do it = 1, NITER
                call operation_leak_body(a, family)
            end do
            call mlx_synchronize()
            call mlx_clear_cache()
            call assert_true(mem0 == mlx_active_memory(), 'operation loop returns active memory exactly')
            call assert_int(live0, mlx_live_count(), 'operation loop returns live handles exactly')
            call assert_int(stale0, registry_stale_releases(), 'operation loop has no stale release')
        end do
    end subroutine test_operation_leaks

    ! one evaluated expression of each operation family
    subroutine operation_leak_body( a, family )
        type(mlx_array), intent(in) :: a
        integer,         intent(in) :: family
        type(mlx_array) :: r
        select case(family)
            case(1)
                r = sum(sqrt(reshape(a, [4, 3])+2._real64), dim=1)
            case(2)
                r = matmul(transpose(a), a)
            case(3)
                r = mlx_irfft(mlx_rfft(a, 1), 1)
        end select
        call mlx_eval(r)
    end subroutine operation_leak_body

    ! a compiled function applied 10,000 times leaks no handle, stale release or byte, closures included
    subroutine test_compiled_leak
        type(mlx_function) :: f, g
        type(mlx_array)    :: a
        real(real32)       :: x(4, 3)
        integer            :: it, live0, stale0, entry_live, entry_stale
        integer(int64)     :: mem0, entry_mem
        write(*,'(a)') 'test_compiled_leak'
        call mlx_synchronize()
        call mlx_clear_cache()
        entry_live = mlx_live_count()
        entry_stale = registry_stale_releases()
        entry_mem = mlx_active_memory()
        x = 0.25_real32
        a = mlx_from(x)
        f = mlx_function(leak_callback)
        g = mlx_compile(f, shapeless=.true.)
        call compiled_leak_body(g, a)
        call mlx_synchronize()
        call mlx_clear_cache()
        live0 = mlx_live_count()
        stale0 = registry_stale_releases()
        mem0 = mlx_active_memory()
        do it = 1, NITER
            call compiled_leak_body(g, a)
        end do
        call mlx_synchronize()
        call mlx_clear_cache()
        call assert_int(live0, mlx_live_count(), 'compiled-call loop returns live handles exactly')
        call assert_int(stale0, registry_stale_releases(), 'compiled-call loop has no stale release')
        call assert_true(mem0 == mlx_active_memory(), 'compiled-call loop returns active memory exactly')
        call g%kill()
        call f%kill()
        call a%kill()
        call mlx_synchronize()
        call mlx_clear_cache()
        call assert_int(entry_live, mlx_live_count(), 'compiled closure teardown returns live handles exactly')
        call assert_int(entry_stale, registry_stale_releases(), 'compiled closure teardown has no stale release')
        call assert_true(entry_mem == mlx_active_memory(), 'compiled closure teardown returns active memory exactly')
    end subroutine test_compiled_leak

    ! one compiled application, evaluated
    subroutine compiled_leak_body( f, a )
        type(mlx_function), intent(in) :: f
        type(mlx_array),    intent(in) :: a
        type(mlx_array), allocatable :: outputs(:)
        call f%apply([a], outputs)
        call mlx_eval(outputs)
    end subroutine compiled_leak_body

    ! the affine callback the compiled leak loop applies
    subroutine leak_callback( inputs, outputs, status )
        type(mlx_array), intent(in)               :: inputs(:)
        integer,         intent(out)              :: status
        type(mlx_array), allocatable, intent(out) :: outputs(:)
        allocate(outputs(1))
        outputs(1) = inputs(1)*2._real32+1._real32
        status = 0
    end subroutine leak_callback

end module mlxf_array_tester
