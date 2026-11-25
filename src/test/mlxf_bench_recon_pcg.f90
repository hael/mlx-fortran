!@descr: benchmark of the reconstruction's PCG solve at SIMPLE's boxes: the padded transforms of the operator
! mlxf_test_exec test=bench_recon_pcg suite=transform [n=] [device=] [repeats=] [revision=]: one forward real
! transform of the native volume zero-padded to the lattice of m = 2 n, its inverse and the crop back to n, per
! box and device: the spectrum's shape, the round trip's error, the times of repeated evaluations and whether
! their bits agree, MLX's peak, active and cache memory. A key the suite does not read stops the program. Rows
! are appended to ./bench_recon_pcg.tsv; times never pass or fail.
module mlxf_bench_recon_pcg
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use, intrinsic :: iso_c_binding,   only: c_int, c_double
use mlxf,             only: mlx_array, mlx_from, mlx_to, mlx_eval, mlx_rfftn, mlx_irfftn, mlx_slice, &
                            mlx_set_default_device, mlx_peak_memory, mlx_reset_peak_memory, mlx_active_memory, &
                            mlx_cache_memory, mlx_clear_cache
use mlxf_test_defs,   only: RECON_PCG_BENCH_N, ELEM_CEILING
use mlxf_test_utils,  only: assert_true, test_devices, device_name, bits_equal, seeded_uniform
use mlxf_test_reduce, only: nan_maxval
implicit none
private

public :: run_bench_recon_pcg

! the keys each suite reads, blank separated; test and suite belong to the executable
character(len=*), parameter :: SUITE_KEYS(1) = [character(len=96) :: 'transform n device repeats revision']
! the rows' file and the seed of the transformed volume
character(len=*), parameter :: ROWS_FILE   = 'bench_recon_pcg.tsv'
integer,          parameter :: VOLUME_SEED = 1

interface
    integer(c_int) function getloadavg( loadavg, nelem ) bind(c, name='getloadavg')
        import :: c_int, c_double
        real(c_double) :: loadavg(*)
        integer(c_int), value :: nelem
    end function getloadavg
end interface

contains

    subroutine run_bench_recon_pcg( suite, found )
        character(len=*), intent(in)  :: suite
        logical,          intent(out) :: found
        found = .true.
        call check_keys(suite)
        select case( trim(suite) )
            case( 'transform' )
                call bench_transform
            case default
                found = .false.
        end select
    end subroutine run_bench_recon_pcg

    ! ---- arguments ---------------------------------------------------------------------------------------

    ! the value of key=value on the command line, or dflt
    function arg_str( key, dflt ) result(val)
        character(len=*), intent(in) :: key, dflt
        character(len=:), allocatable :: val
        character(len=512)            :: arg
        integer                       :: i
        val = dflt
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            if( index(arg, key//'=') == 1 ) val = trim(arg(len(key)+2:))
        end do
    end function arg_str

    ! every key=value of the command line is one the suite reads; another stops the program with the key's name
    subroutine check_keys( suite )
        character(len=*), intent(in) :: suite
        character(len=512) :: arg
        character(len=96)  :: keys
        integer            :: i, ieq
        keys = ''
        do i = 1, size(SUITE_KEYS)
            if( index(SUITE_KEYS(i), trim(suite)//' ') == 1 ) keys = SUITE_KEYS(i)(len_trim(suite) + 1:)
        end do
        if( len_trim(keys) == 0 ) return
        do i = 1, command_argument_count()
            call get_command_argument(i, arg)
            ieq = index(arg, '=')
            if( ieq > 1 )then
                if( arg(1:ieq-1) == 'test' .or. arg(1:ieq-1) == 'suite' ) cycle
                if( index(' '//trim(keys)//' ', ' '//arg(1:ieq-1)//' ') > 0 ) cycle
            endif
            write(*,'(a)') 'bench_recon_pcg: suite='//trim(suite)//' does not read '//trim(arg)//' (its keys:'//&
                &trim(keys)//')'
            error stop 2
        end do
    end subroutine check_keys

    ! the integer value of key=value, or dflt when the key is absent; a value that is not an integer stops
    integer function arg_int( key, dflt )
        character(len=*), intent(in) :: key
        integer,          intent(in) :: dflt
        character(len=:), allocatable :: s
        integer                       :: ios
        arg_int = dflt
        s       = arg_str(key, '')
        if( len(s) == 0 ) return
        ios = 1
        if( verify(s, '+-0123456789') == 0 ) read(s, *, iostat=ios) arg_int
        if( ios /= 0 )then
            write(*,'(a)') 'bench_recon_pcg: '//key//'='//s//' is not an integer'
            error stop 2
        endif
    end function arg_int

    ! the boxes of n= (one), or both bench boxes
    function arg_boxes() result(ns)
        integer, allocatable :: ns(:)
        integer              :: n
        n = arg_int('n', 0)
        if( n > 0 )then
            if( modulo(n, 2) /= 0 )then
                write(*,'(a)') 'bench_recon_pcg: n= is an even box'
                error stop 2
            endif
            ns = [n]
        else
            ns = RECON_PCG_BENCH_N
        endif
    end function arg_boxes

    real(real64) function clock_s()
        integer(int64) :: count, rate
        call system_clock(count, rate)
        clock_s = real(count, real64) / real(rate, real64)
    end function clock_s

    real function load_average()
        real(c_double) :: l(3)
        load_average = -1.
        if( getloadavg(l, 3_c_int) >= 1 ) load_average = real(l(1))
    end function load_average

    ! opens the rows' file for appending, writing the header when the file is new
    subroutine open_rows( u, header )
        integer,          intent(out) :: u
        character(len=*), intent(in)  :: header
        logical :: exists
        inquire(file=ROWS_FILE, exist=exists)
        open(newunit=u, file=ROWS_FILE, position='append', action='write')
        if( .not. exists ) write(u,'(a)') header
    end subroutine open_rows

    ! ---- suite=transform ---------------------------------------------------------------------------------

    ! per box and device: the padded forward transform, its inverse and the crop, evaluated repeats times after a
    ! warm-up; the spectrum's shape and the round trip are asserted, the rest is recorded
    subroutine bench_transform
        integer, allocatable :: devs(:), ns(:)
        integer              :: idev, in, repeats
        ns      = arg_boxes()
        repeats = max(1, arg_int('repeats', 3))
        call test_devices(devs)
        do idev = 1, size(devs)
            call mlx_set_default_device(devs(idev))
            do in = 1, size(ns)
                call transform_row(ns(in), devs(idev), repeats)
            end do
        end do
    end subroutine bench_transform

    subroutine transform_row( n, dev, repeats )
        integer, intent(in) :: n, dev, repeats
        real(real32),     allocatable :: x(:,:,:), y(:,:,:), y1(:,:,:)
        real(real64),     allocatable :: t(:)
        type(mlx_array)               :: a, s, r, c
        integer,          allocatable :: shp(:)
        integer                       :: m, k, u
        logical                       :: same
        real(real64)                  :: err, t0
        real                          :: load0, load1
        integer(int64)                :: peak, active, cache
        character(len=:), allocatable :: rev
        m = 2 * n
        allocate(x(n, n, n), y(n, n, n), y1(n, n, n), t(repeats))
        x = reshape(real(seeded_uniform(n**3, VOLUME_SEED), real32), [n, n, n])
        call mlx_clear_cache()
        a = mlx_from(x)
        call mlx_eval(a)
        load0 = load_average()
        ! the warm-up: the shape of the spectrum, Fortran's view with the halved dimension first
        s   = mlx_rfftn(a, n=[m, m, m])
        shp = s%shape()
        r   = mlx_irfftn(s, n=[m, m, m])
        c   = mlx_slice(r, [1, 1, 1], [n, n, n])
        call mlx_to(y1, c)
        call assert_true(size(shp) == 3, 'transform: the padded spectrum has rank 3')
        if( size(shp) == 3 ) call assert_true(all(shp == [m/2 + 1, m, m]), &
            'transform: the padded spectrum has the shape (m/2 + 1, m, m), the halved dimension first')
        call mlx_reset_peak_memory()
        same = .true.
        do k = 1, repeats
            t0 = clock_s()
            s  = mlx_rfftn(a, n=[m, m, m])
            r  = mlx_irfftn(s, n=[m, m, m])
            c  = mlx_slice(r, [1, 1, 1], [n, n, n])
            call mlx_eval(c)
            t(k) = clock_s() - t0
            call mlx_to(y, c)
            same = same .and. all(bits_equal(y, y1))
        end do
        peak   = mlx_peak_memory()
        active = mlx_active_memory()
        cache  = mlx_cache_memory()
        load1  = load_average()
        err    = nan_maxval(real(abs(y - x), real64)) / nan_maxval(real(abs(x), real64))
        call assert_true(err <= ELEM_CEILING, 'transform: the padded round trip returns the volume within 64 float32 '//&
            'epsilons of its largest value')
        rev = arg_str('revision', 'unknown')
        call open_rows(u, 'suite'//achar(9)//'n'//achar(9)//'m'//achar(9)//'device'//achar(9)//'spectrum_shape'//&
            &achar(9)//'roundtrip_err'//achar(9)//'best_s'//achar(9)//'spread_s'//achar(9)//'times_s'//achar(9)//&
            &'bits_equal'//achar(9)//'peak_b'//achar(9)//'active_b'//achar(9)//'cache_b'//achar(9)//'load1_before'//&
            &achar(9)//'load1_after'//achar(9)//'revision')
        write(u,'(a,i0,a,i0,a,a,a,3(i0,a),es11.4e2,a,f0.6,a,f0.6,a,*(f0.6,:,","))', advance='no') 'transform'//&
            &achar(9), n, achar(9), m, achar(9), device_name(dev), achar(9), shp(1), 'x', shp(2), 'x', shp(3), achar(9), &
            err, achar(9), minval(t), achar(9), maxval(t) - minval(t), achar(9), t
        write(u,'(a,l1,3(a,i0),2(a,f0.2),a,a)') achar(9), same, achar(9), peak, achar(9), active, achar(9), cache, &
            achar(9), load0, achar(9), load1, achar(9), rev
        close(u)
        write(*,'(a,i0,a,i0,3a,es10.3,a,f9.4,a,f9.4,a,l1,a,es10.3)') 'transform n=', n, ' m=', m, ' ', &
            device_name(dev), ': round trip ', err, ', best ', minval(t), ' s, spread ', maxval(t) - minval(t), &
            ' s, bits equal ', same, ', peak ', real(peak, real64)
    end subroutine transform_row

end module mlxf_bench_recon_pcg
