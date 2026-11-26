!@descr: the crossover of BLAS and MLX matrix products: sgemm and cgemm on the host against matmul on MLX's devices
! mlxf_test_exec test=bench_blas suite=crossover [nmax=4096] [device=cpu|gpu|all]. A measurement: it asserts nothing.
! Square products n = 32 to nmax (doubling) in float32 and complex64, and SIMPLE's polar block product (the
! conjugate transpose of a 2nk x 16 block times a 2nk x 32 tile, over the pftsz + 1 rotations), timed on the host
! (the system's CBLAS when the build links one, else Fortran's matmul) and through mlx with the data moved from and
! to Fortran arrays and without it; best of 3 after a warm-up, rows to ./bench_blas.tsv, the crossovers printed.
module mlxf_bench_blas
use, intrinsic :: iso_c_binding,   only: c_int, c_float, c_float_complex
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_eval, matmul, conjg, transpose, mlx_set_default_device, &
                            MLX_DEVICES
use mlxf_test_defs,   only: BLAS_POLAR_NB, BLAS_POLAR_NR, BLAS_POLAR_N2K, BLAS_POLAR_N1
use mlxf_test_utils,  only: set_fixed_seed, test_devices, device_name
use mlxf_test_reduce, only: nan_maxval
implicit none
private

public :: run_bench_blas

#ifdef MLXF_HAVE_BLAS
! CBLAS, the C interface of the system's BLAS (Accelerate on macOS): the order, the transposes, the sizes and the
! leading dimensions by value; cgemm takes its scalars by reference
interface
    subroutine cblas_sgemm( order, transa, transb, m, n, k, alpha, a, lda, b, ldb, beta, c, ldc ) bind(c, name='cblas_sgemm')
        import :: c_int, c_float
        integer(c_int), value         :: order, transa, transb, m, n, k, lda, ldb, ldc
        real(c_float),  value         :: alpha, beta
        real(c_float),  intent(in)    :: a(*), b(*)
        real(c_float),  intent(inout) :: c(*)
    end subroutine cblas_sgemm

    subroutine cblas_cgemm( order, transa, transb, m, n, k, alpha, a, lda, b, ldb, beta, c, ldc ) bind(c, name='cblas_cgemm')
        import :: c_int, c_float_complex
        integer(c_int),           value         :: order, transa, transb, m, n, k, lda, ldb, ldc
        complex(c_float_complex), intent(in)    :: alpha, beta
        complex(c_float_complex), intent(in)    :: a(*), b(*)
        complex(c_float_complex), intent(inout) :: c(*)
    end subroutine cblas_cgemm
end interface

! CBLAS's enumerators: column-major order, no transpose, conjugate transpose
integer(c_int),   parameter :: COL_MAJOR = 102_c_int, NO_TRANS = 111_c_int, CONJ_TRANS = 113_c_int
character(len=*), parameter :: HOST_ROUTE = 'cblas'
#else
character(len=*), parameter :: HOST_ROUTE = 'matmul'
#endif

! the products, the first square size, the passes (a warm-up, then the best of the rest), the floating-point work
! one timing aims at (repeating a fast product), the most repeats, the seed of the operands
character(len=5), parameter :: KINDS(3)   = [character(len=5) :: 'sgemm', 'cgemm', 'polar']
integer,          parameter :: NMIN       = 32
integer,          parameter :: NPASS      = 3
real(real64),     parameter :: WORK_AIM   = 2.e9_real64
integer,          parameter :: MAX_REPS   = 1000
integer,          parameter :: BLAS_SEED  = 23
character(len=1), parameter :: T          = achar(9)

! one product's operands and results: kind, sizes (m, n, k, batch), real or complex operands, the host's result
! and the result brought back from MLX
type :: blas_case
    character(len=5)             :: kind = ''
    integer                      :: m = 0, n = 0, k = 0, nb = 1
    real(real32),    allocatable :: ra(:,:), rb(:,:), rc(:,:), rd(:,:)
    complex(real32), allocatable :: ca(:,:,:), cb(:,:,:), cc(:,:,:), cd(:,:,:)
end type blas_case

contains

    subroutine run_bench_blas( mode, found )
        character(len=*), intent(in)  :: mode
        logical,          intent(out) :: found
        integer,          allocatable :: devs(:)
        real(real64),     allocatable :: secs(:,:,:)
        type(blas_case)               :: bc
        character(len=512)            :: arg
        integer                       :: i, nmax, nsize, ik, is, u
        found = trim(mode) == 'crossover'
        if( .not. found ) return
        nmax = 4096
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            if( index(arg, 'test=') == 1 .or. index(arg, 'suite=') == 1 .or. index(arg, 'device=') == 1 ) cycle
            if( index(arg, 'nmax=') == 1 )then
                read(arg(6:), *) nmax
                cycle
            endif
            write(*,'(a)') 'bench_blas: suite=crossover reads nmax= and device= only: '//trim(arg)
            error stop 2
        end do
        call test_devices(devs)
        nsize = 0
        do while( NMIN * 2**nsize <= nmax )
            nsize = nsize + 1
        end do
        write(*,'(a,i0,2a)') '**** bench_blas suite=crossover, n up to ', nmax, ', host route ', HOST_ROUTE
        call set_fixed_seed(BLAS_SEED)
        call open_rows(u)
        ! seconds per product: (route, size, kind); route 1 the host, then per device without and with transfer
        allocate(secs(1 + 2*size(devs), nsize + 1, size(KINDS)))
        secs = -1._real64
        do ik = 1, size(KINDS)
            do is = 1, merge(nsize, 1, KINDS(ik) /= 'polar')
                call new_case(bc, KINDS(ik), NMIN * 2**(is - 1))
                call measure(bc, devs, secs(:, is, ik), u)
            end do
        end do
        close(u)
        call report_crossovers(secs, devs, nsize)
    end subroutine run_bench_blas

    ! the operands of one product, seeded: a square n x n product, or the polar block product batched
    subroutine new_case( bc, kind, n )
        type(blas_case),  intent(inout) :: bc
        character(len=*), intent(in)    :: kind
        integer,          intent(in)    :: n
        real(real32), allocatable :: re(:,:,:), im(:,:,:)
        bc%kind = kind
        if( allocated(bc%ra) ) deallocate(bc%ra, bc%rb, bc%rc, bc%rd)
        if( allocated(bc%ca) ) deallocate(bc%ca, bc%cb, bc%cc, bc%cd)
        select case( kind )
            case( 'sgemm' )
                bc%m = n
                bc%n = n
                bc%k = n
                bc%nb = 1
                allocate(bc%ra(n, n), bc%rb(n, n), bc%rc(n, n), bc%rd(n, n))
                call random_number(bc%ra)
                call random_number(bc%rb)
            case( 'cgemm' )
                bc%m = n
                bc%n = n
                bc%k = n
                bc%nb = 1
                allocate(re(n, n, 1), im(n, n, 1))
                call random_number(re)
                call random_number(im)
                bc%ca = cmplx(re, im, real32)
                call random_number(re)
                call random_number(im)
                bc%cb = cmplx(re, im, real32)
                allocate(bc%cc(n, n, 1), bc%cd(n, n, 1))
            case default
                bc%m = BLAS_POLAR_NB
                bc%n = BLAS_POLAR_NR
                bc%k = BLAS_POLAR_N2K
                bc%nb = BLAS_POLAR_N1
                allocate(re(bc%k, bc%m, bc%nb), im(bc%k, bc%m, bc%nb))
                call random_number(re)
                call random_number(im)
                bc%ca = cmplx(re, im, real32)
                deallocate(re, im)
                allocate(re(bc%k, bc%n, bc%nb), im(bc%k, bc%n, bc%nb))
                call random_number(re)
                call random_number(im)
                bc%cb = cmplx(re, im, real32)
                allocate(bc%cc(bc%m, bc%n, bc%nb), bc%cd(bc%m, bc%n, bc%nb))
        end select
    end subroutine new_case

    ! the product's seconds on the host and on each device without and with transfer, one row each
    subroutine measure( bc, devs, secs, u )
        type(blas_case), intent(inout) :: bc
        integer,         intent(in)    :: devs(:)
        real(real64),    intent(inout) :: secs(:)
        integer,         intent(in)    :: u
        type(mlx_array) :: xa, xb
        real(real64)    :: work, diff
        integer         :: reps, id, pass, r
        logical         :: moved
        integer(int64)  :: t0, t1, rate
        work = 2._real64 * bc%m * bc%n * bc%k * bc%nb
        if( bc%kind /= 'sgemm' ) work = 4._real64 * work
        reps = max(1, min(MAX_REPS, nint(WORK_AIM / work)))
        secs(1) = huge(1._real64)
        do pass = 0, NPASS
            call system_clock(t0, rate)
            do r = 1, reps
                call host_product(bc)
            end do
            call system_clock(t1)
            if( pass > 0 ) secs(1) = min(secs(1), real(t1 - t0, real64) / real(rate, real64) / reps)
        end do
        call write_row(u, bc, 'host '//HOST_ROUTE, [secs(1), work, 0._real64])
        do id = 1, size(devs)
            call mlx_set_default_device(devs(id))
            call resident(bc, xa, xb)
            do r = 0, 1
                moved = r == 1
                secs(1 + 2*(id - 1) + 1 + r) = huge(1._real64)
                do pass = 0, NPASS
                    call system_clock(t0, rate)
                    call mlx_products(bc, xa, xb, moved, reps)
                    call system_clock(t1)
                    if( pass > 0 ) secs(1 + 2*(id - 1) + 1 + r) = min(secs(1 + 2*(id - 1) + 1 + r), &
                        &real(t1 - t0, real64) / real(rate, real64) / reps)
                end do
                diff = rel_diff(bc)
                call write_row(u, bc, device_name(devs(id))//' '//merge('transfer', 'resident', moved), &
                    &[secs(1 + 2*(id - 1) + 1 + r), work, diff])
            end do
        end do
    end subroutine measure

    ! the host's product into rc or cc
    subroutine host_product( bc )
        type(blas_case), intent(inout) :: bc
        integer :: j
#ifdef MLXF_HAVE_BLAS
        select case( bc%kind )
            case( 'sgemm' )
                call cblas_sgemm(COL_MAJOR, NO_TRANS, NO_TRANS, bc%m, bc%n, bc%k, 1._c_float, bc%ra, bc%m, bc%rb, &
                    &bc%k, 0._c_float, bc%rc, bc%m)
            case( 'cgemm' )
                call cblas_cgemm(COL_MAJOR, NO_TRANS, NO_TRANS, bc%m, bc%n, bc%k, (1._c_float, 0._c_float), bc%ca, &
                    &bc%m, bc%cb, bc%k, (0._c_float, 0._c_float), bc%cc, bc%m)
            case default
                do j = 1, bc%nb
                    call cblas_cgemm(COL_MAJOR, CONJ_TRANS, NO_TRANS, bc%m, bc%n, bc%k, (1._c_float, 0._c_float), &
                        &bc%ca(:,:, j), bc%k, bc%cb(:,:, j), bc%k, (0._c_float, 0._c_float), bc%cc(:,:, j), bc%m)
                end do
        end select
#else
        select case( bc%kind )
            case( 'sgemm' )
                bc%rc = matmul(bc%ra, bc%rb)
            case( 'cgemm' )
                bc%cc(:,:, 1) = matmul(bc%ca(:,:, 1), bc%cb(:,:, 1))
            case default
                do j = 1, bc%nb
                    bc%cc(:,:, j) = matmul(conjg(transpose(bc%ca(:,:, j))), bc%cb(:,:, j))
                end do
        end select
#endif
    end subroutine host_product

    ! the operands on the default device, evaluated, for the products without transfer
    subroutine resident( bc, xa, xb )
        type(blas_case), intent(in)    :: bc
        type(mlx_array), intent(inout) :: xa, xb
        if( bc%kind == 'sgemm' )then
            xa = mlx_from(bc%ra)
            xb = mlx_from(bc%rb)
        else
            xa = mlx_from(bc%ca)
            xb = mlx_from(bc%cb)
        endif
        call mlx_eval(xa)
        call mlx_eval(xb)
    end subroutine resident

    ! reps products on the default device: with moved, each from Fortran arrays to the Fortran result (rd or cd);
    ! without, of the resident operands, evaluated; the last product is brought back either way
    subroutine mlx_products( bc, xa, xb, moved, reps )
        type(blas_case), intent(inout) :: bc
        type(mlx_array), intent(in)    :: xa, xb
        logical,         intent(in)    :: moved
        integer,         intent(in)    :: reps
        type(mlx_array) :: a, b, p
        integer         :: r
        do r = 1, reps
            if( moved )then
                if( bc%kind == 'sgemm' )then
                    a = mlx_from(bc%ra)
                    b = mlx_from(bc%rb)
                else
                    a = mlx_from(bc%ca)
                    b = mlx_from(bc%cb)
                endif
            else
                a = xa
                b = xb
            endif
            if( bc%kind == 'polar' )then
                p = matmul(conjg(transpose(a)), b)
            else
                p = matmul(a, b)
            endif
            if( moved )then
                if( bc%kind == 'sgemm' )then
                    call mlx_to(bc%rd, p)
                else
                    call mlx_to(bc%cd, p)
                endif
            else
                call mlx_eval(p)
            endif
        end do
        if( .not. moved )then
            if( bc%kind == 'sgemm' )then
                call mlx_to(bc%rd, p)
            else
                call mlx_to(bc%cd, p)
            endif
        endif
    end subroutine mlx_products

    ! the largest difference of MLX's result from the host's, over the host's largest magnitude
    real(real64) function rel_diff( bc )
        type(blas_case), intent(in) :: bc
        if( bc%kind == 'sgemm' )then
            rel_diff = real(nan_maxval(abs(bc%rd - bc%rc)), real64) / real(nan_maxval(abs(bc%rc)), real64)
        else
            rel_diff = real(nan_maxval(abs(bc%cd - bc%cc)), real64) / real(nan_maxval(abs(bc%cc)), real64)
        endif
    end function rel_diff

    subroutine open_rows( u )
        integer, intent(out) :: u
        logical :: exists
        inquire(file='bench_blas.tsv', exist=exists)
        open(newunit=u, file='bench_blas.tsv', position='append', action='write')
        if( .not. exists ) write(u,'(a)') 'product'//T//'m'//T//'n'//T//'k'//T//'batch'//T//'device'//T//'route'//&
            &T//'seconds'//T//'gflops'//T//'rel_diff'
    end subroutine open_rows

    ! one row: the product, where it ran (host route, or device and transfer), seconds, GFLOP/s, the difference
    subroutine write_row( u, bc, label, vals )
        integer,          intent(in) :: u
        type(blas_case),  intent(in) :: bc
        character(len=*), intent(in) :: label
        real(real64),     intent(in) :: vals(3)
        character(len=32) :: s, g, d, dev, route
        read(label, *) dev, route
        write(s,'(es12.5)') vals(1)
        write(g,'(f12.3)') vals(2) / vals(1) * 1.e-9_real64
        write(d,'(es10.3)') vals(3)
        write(u,'(a,4(a,i0),5a)') trim(bc%kind), T, bc%m, T, bc%n, T, bc%k, T, bc%nb, T//trim(dev), T//trim(route), &
            &T//trim(adjustl(s)), T//trim(adjustl(g)), T//trim(adjustl(d))
        write(*,'(a,a6,a,i5,a,i5,a,i5,a,i4,a,a4,a,a9,a,es11.4,a,f10.2,a,es9.2)') '    ', trim(bc%kind), ' m', bc%m, &
            &' n', bc%n, ' k', bc%k, ' batch', bc%nb, ' ', trim(dev), ' ', trim(route), ' s', vals(1), ' GFLOP/s', &
            &vals(2) / vals(1) * 1.e-9_real64, ' rel_diff', vals(3)
    end subroutine write_row

    ! per product, device and transfer, the first square size at which MLX's product takes less time than the
    ! host's; the polar block product's time on each route against the host's
    subroutine report_crossovers( secs, devs, nsize )
        real(real64), intent(in) :: secs(:,:,:)
        integer,      intent(in) :: devs(:)
        integer,      intent(in) :: nsize
        integer :: ik, id, r, is, route, first
        write(*,'(a)') '    crossover: the first n at which MLX is faster than the host ('//HOST_ROUTE//')'
        do ik = 1, 2
            do id = 1, size(devs)
                do r = 0, 1
                    route = 1 + 2*(id - 1) + 1 + r
                    first = 0
                    do is = 1, nsize
                        if( secs(route, is, ik) < secs(1, is, ik) )then
                            first = NMIN * 2**(is - 1)
                            exit
                        endif
                    end do
                    if( first > 0 )then
                        write(*,'(a,a6,a,a4,a,a9,a,i0)') '    crossover ', trim(KINDS(ik)), ' ', device_name(devs(id)), &
                            &' ', merge('transfer', 'resident', r == 1), ' n = ', first
                    else
                        write(*,'(a,a6,a,a4,a,a9,a,i0)') '    crossover ', trim(KINDS(ik)), ' ', device_name(devs(id)), &
                            &' ', merge('transfer', 'resident', r == 1), ' none up to n = ', NMIN * 2**(nsize - 1)
                    endif
                end do
            end do
        end do
        do id = 1, size(devs)
            do r = 0, 1
                route = 1 + 2*(id - 1) + 1 + r
                write(*,'(a,a4,a,a9,a,f8.3)') '    polar block product ', device_name(devs(id)), ' ', &
                    &merge('transfer', 'resident', r == 1), ': host time / MLX time = ', secs(1, 1, 3) / secs(route, 1, 3)
            end do
        end do
    end subroutine report_crossovers

end module mlxf_bench_blas
