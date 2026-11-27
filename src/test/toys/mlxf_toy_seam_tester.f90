!@descr: tests of the toys' seam: the opaque device state's lifecycle on a test double, each class's backends, refusals and cycles
! The double is a device type of this tester: it extends device_work and holds one MLX array. A holder keeps a
! scalar and an array class(device_work), allocatable, as a toy class does, kills every element before it
! deallocates and resolves the dynamic type where it needs the device. The checks count the registry's live
! handles: an explicit kill releases them whatever the compiler finalizes afterwards. Of each toy class (the
! calculator, the projector, the reconstructor): 1,000 cycles of new and kill leave the registry's count as it was,
! the host backend makes no device object, and what the host backend cannot do is refused with a message.
module mlxf_toy_seam_tester
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf,                       only: mlx_array, mlx_from, mlx_to, mlx_eval, mlx_live_count, mlx_active_memory, &
                                      mlx_synchronize, mlx_set_default_device, mlx_default_device, mlx_clear_cache, sum
use mlxf_test_defs,             only: POLARFT_REF_ROUTES, parameters
use mlxf_toy_device_work,       only: device_work
use mlxf_toy_polarft_calc,      only: polarft_calc
use mlxf_toy_projector,         only: projector
use mlxf_toy_reconstructor_pcg, only: reconstructor_pcg
use mlxf_test_utils,            only: assert_true, assert_int, device_name, test_devices
implicit none
private
public :: run_all_seam_tests

! the cycles of the lifecycle checks, and how often a cycle of a class also makes its device arrays
integer, parameter :: NCYCLES    = 1000
integer, parameter :: FULL_EVERY = 100
! the cycles of a shift map's lifecycle
integer, parameter :: NMAPCYCLES = 100
! the classes' smallest fixtures: a calculator of two references and two particles on a ring of eight samples
integer, parameter :: C_PFTSZ = 4
integer, parameter :: C_NK    = 2
integer, parameter :: C_NREFS = 2
! a projector of a 4-cube padded to 8
integer, parameter :: P_N = 4
! a reconstructor of a 4-cube on the padded lattice of 8
integer, parameter :: R_N = 4

! the double of a workspace: one device array, and how often its kill released one
type, extends(device_work) :: work_double
    logical         :: exists = .false.
    integer         :: nreleased = 0
    type(mlx_array) :: bank
  contains
    procedure :: new  => work_double_new
    procedure :: kill => work_double_kill
    final     :: work_double_final
end type work_double

! another extension, which no holder expects
type, extends(device_work) :: work_stranger
  contains
    procedure :: kill => work_stranger_kill
end type work_stranger

! the double of a toy class: its device state, opaque
type :: holder
    class(device_work), allocatable :: w
    class(device_work), allocatable :: ws(:)
  contains
    procedure :: new    => holder_new
    procedure :: total  => holder_total
    procedure :: kill   => holder_kill
    final     :: holder_final
end type holder

contains

    subroutine run_all_seam_tests
        integer, allocatable :: devs(:)
        integer              :: i, original
        write(*,'(a)') '**** running all seam tests ****'
        call test_devices(devs)
        original = mlx_default_device()
        do i = 1, size(devs)
            call mlx_set_default_device(devs(i))
            write(*,'(a)') '  on the '//device_name(devs(i))
            call test_opaque_lifecycle(devs(i))
            call test_wrong_type(devs(i))
            call test_polarft_calc(devs(i))
            call test_polarft_maps(devs(i))
            call test_projector(devs(i))
            call test_reconstructor_pcg(devs(i))
        end do
        call mlx_set_default_device(original)
    end subroutine run_all_seam_tests

    ! ---- the doubles ---------------------------------------------------------------------------------------------

    subroutine work_double_new( self, x )
        class(work_double), intent(inout) :: self
        real(real32),       intent(in)    :: x(:)
        call self%kill()
        self%bank = mlx_from(x)
        call mlx_eval(self%bank)
        self%exists = .true.
    end subroutine work_double_new

    subroutine work_double_kill( self )
        class(work_double), intent(inout) :: self
        if( .not. self%exists ) return
        call self%bank%kill()
        self%exists    = .false.
        self%nreleased = self%nreleased + 1
    end subroutine work_double_kill

    subroutine work_double_final( self )
        type(work_double), intent(inout) :: self
        call self%kill()
    end subroutine work_double_final

    subroutine work_stranger_kill( self )
        class(work_stranger), intent(inout) :: self
    end subroutine work_stranger_kill

    ! the device state made: a scalar and two elements, each with its array; stranger makes the scalar of the type
    ! no holder expects
    subroutine holder_new( self, x, stranger )
        class(holder), intent(inout) :: self
        real(real32),  intent(in)    :: x(:)
        logical,       intent(in)    :: stranger
        integer :: i
        call self%kill()
        if( stranger )then
            allocate(work_stranger :: self%w)
        else
            allocate(work_double :: self%w)
        endif
        allocate(work_double :: self%ws(2))
        select type( w => self%w )
            type is( work_double )
                call w%new(x)
        end select
        select type( ws => self%ws )
            type is( work_double )
                do i = 1, size(ws)
                    call ws(i)%new(real(i, real32) * x)
                end do
        end select
    end subroutine holder_new

    ! the sum of the three arrays, from the device; status 1 and msg when the device state is not the double's
    subroutine holder_total( self, total, status, msg )
        class(holder),                 intent(inout) :: self
        real(real32),                  intent(out)   :: total
        integer,                       intent(out)   :: status
        character(len=:), allocatable, intent(out)   :: msg
        type(mlx_array) :: s
        real(real32)    :: v(1)
        total  = 0._real32
        status = 1
        msg    = 'holder: no device state'
        if( .not. allocated(self%w) .or. .not. allocated(self%ws) ) return
        msg = 'holder: the device state is not a work_double'
        select type( w => self%w )
            type is( work_double )
                select type( ws => self%ws )
                    type is( work_double )
                        s = sum(w%bank) + sum(ws(1)%bank) + sum(ws(2)%bank)
                        call mlx_to(v, reshape_one(s), status=status)
                        total = v(1)
                        msg   = ''
                end select
        end select
    end subroutine holder_total

    function reshape_one( s ) result(r)
        use mlxf, only: reshape
        type(mlx_array), intent(in) :: s
        type(mlx_array) :: r
        r = reshape(s, [1])
    end function reshape_one

    ! every element killed, then deallocated: the handles' release does not rest on finalization
    subroutine holder_kill( self )
        class(holder), intent(inout) :: self
        integer :: i
        if( allocated(self%w) )then
            call self%w%kill()
            deallocate(self%w)
        endif
        if( allocated(self%ws) )then
            do i = 1, size(self%ws)
                call self%ws(i)%kill()
            end do
            deallocate(self%ws)
        endif
    end subroutine holder_kill

    subroutine holder_final( self )
        type(holder), intent(inout) :: self
        call self%kill()
    end subroutine holder_final

    ! ---- the tests -----------------------------------------------------------------------------------------------

    ! new, a device result, kill (twice), a holder left to its final procedure, an intent(out) dummy, and 1,000
    ! cycles: the live handles and the active memory return
    subroutine test_opaque_lifecycle( dev )
        integer, intent(in) :: dev
        type(holder)                  :: h
        real(real32)                  :: x(8), total
        character(len=:), allocatable :: msg
        integer                       :: live0, st, i
        integer(int64)                :: mem0, mem1
        write(*,'(a)') 'test_opaque_lifecycle'
        x     = [(real(i, real32), i = 1, 8)]
        live0 = mlx_live_count()
        call h%new(x, .false.)
        call assert_int(live0 + 3, mlx_live_count(), device_name(dev)//': the holder''s device state holds three arrays')
        call h%total(total, st, msg)
        call assert_true(st == 0 .and. abs(total - 144._real32) <= 1.e-3_real32, device_name(dev)//': the device '// &
            &'state is reached through its dynamic type (the sum is 36 + 36 + 72)')
        call h%kill()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': an explicit kill releases every array of the '// &
            &'opaque components')
        call h%kill()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': kill is idempotent')
        call h%new(x, .false.)
        call h%new(x, .false.)
        call assert_int(live0 + 3, mlx_live_count(), device_name(dev)//': new on a holder in use releases its '// &
            &'device state first')
        call h%kill()
        call scope_exit(x)
        call assert_int(live0, mlx_live_count(), device_name(dev)//': a holder that leaves its scope releases its '// &
            &'device state through its final procedure')
        call h%new(x, .false.)
        call take_out(h)
        call assert_int(live0, mlx_live_count(), device_name(dev)//': a holder passed to an intent(out) dummy '// &
            &'releases its device state')
        ! the device releases a buffer when the work that used it completes: wait before each sample
        call mlx_synchronize()
        mem0 = mlx_active_memory()
        do i = 1, NCYCLES
            call h%new(x, .false.)
            call h%kill()
        end do
        call mlx_synchronize()
        mem1 = mlx_active_memory()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': 1,000 cycles of new and kill leave the live '// &
            &'handles as they were')
        call assert_true(mem1 == mem0, device_name(dev)//': 1,000 cycles of new and kill leave the active memory '// &
            &'as it was')
    end subroutine test_opaque_lifecycle

    subroutine scope_exit( x )
        real(real32), intent(in) :: x(:)
        type(holder) :: loc
        call loc%new(x, .false.)
    end subroutine scope_exit

    subroutine take_out( h )
        type(holder), intent(out) :: h
    end subroutine take_out

    ! a device state of another type is found by the holder and refused with a message; kill still releases all
    subroutine test_wrong_type( dev )
        integer, intent(in) :: dev
        type(holder)                  :: h
        real(real32)                  :: x(4), total
        character(len=:), allocatable :: msg
        integer                       :: live0, st
        write(*,'(a)') 'test_wrong_type'
        x     = 1._real32
        live0 = mlx_live_count()
        call h%new(x, .true.)
        call h%total(total, st, msg)
        call assert_true(st /= 0 .and. index(msg, 'not a work_double') > 0, device_name(dev)//': a device state of '// &
            &'another type is refused with a message')
        call h%kill()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': kill releases the device state whatever its '// &
            &'dynamic type')
    end subroutine test_wrong_type

    ! ---- the polar calculator ------------------------------------------------------------------------------------

    ! a calculator of the smallest fixture on the backend l_mlx; full also sets and memoizes its references (on
    ! the MLX backend with the device tiles); nbad counts the refusals
    subroutine small_calc( pftc, l_mlx, full, nbad )
        type(polarft_calc), intent(inout) :: pftc
        logical,            intent(in)    :: l_mlx, full
        integer,            intent(inout) :: nbad
        complex(real64) :: pft(C_PFTSZ, C_NK)
        integer         :: iref, ieo, j, k
        call pftc%new(parameters(pftsz=C_PFTSZ, box=2 * C_PFTSZ, l_mlx=l_mlx), C_NREFS, [1, 2], [1, C_NK])
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
        if( .not. full ) return
        do ieo = 1, 2
            do iref = 1, C_NREFS
                do k = 1, C_NK
                    do j = 1, C_PFTSZ
                        pft(j, k) = cmplx(real(j + iref, real64), real(k - ieo, real64) / 4._real64, real64)
                    end do
                end do
                call pftc%set_ref_pft(iref, pft, ieo == 1)
                if( len(pftc%message()) > 0 ) nbad = nbad + 1
            end do
        end do
        call pftc%memoize_refs()
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
    end subroutine small_calc

    ! the calculator's cycles on the MLX backend, the host backend's device silence, and its refusals
    subroutine test_polarft_calc( dev )
        integer, intent(in) :: dev
        type(polarft_calc)        :: pftc
        real(real32)              :: dists(C_NREFS, 1), temps(1)
        real(real64), allocatable :: xy(:,:)
        integer                   :: irots(C_NREFS, 1), live0, nbad, i
        integer(int64)            :: mem0, mem1
        write(*,'(a)') 'test_polarft_calc'
        nbad  = 0
        live0 = mlx_live_count()
        call small_calc(pftc, .true., .true., nbad)
        call assert_true(mlx_live_count() > live0, device_name(dev)//': polarft_calc on the MLX backend holds device '// &
            &'arrays once its reference tiles are made')
        call pftc%kill()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': polarft_calc%kill releases them')
        call mlx_synchronize()
        mem0 = mlx_active_memory()
        do i = 1, NCYCLES
            call small_calc(pftc, .true., mod(i, FULL_EVERY) == 0, nbad)
            call pftc%kill()
        end do
        call mlx_synchronize()
        mem1 = mlx_active_memory()
        call assert_int(0, nbad, device_name(dev)//': polarft_calc: every cycle was carried out')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': polarft_calc: 1,000 cycles of new and kill '// &
            &'leave the live handles as they were')
        call assert_true(mem1 == mem0, device_name(dev)//': polarft_calc: 1,000 cycles of new and kill leave the '// &
            &'active memory as it was')
        ! the host backend: no device object from new to kill, and what needs the device is refused
        call small_calc(pftc, .false., .true., nbad)
        call assert_int(0, nbad, device_name(dev)//': polarft_calc on the host backend is made, set and memoized')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': polarft_calc on the host backend makes no '// &
            &'device object')
        call pftc%set_ref_route(POLARFT_REF_ROUTES%device)
        call assert_true(index(pftc%message(), 'MLX backend') > 0, device_name(dev)//': the device route is refused '// &
            &'on the host backend')
        call pftc%new_shiftmap(1, [0._real64, 1._real64], 8, C_NK)
        call assert_true(index(pftc%message(), 'MLX backend') > 0, device_name(dev)//': a shift map is refused on '// &
            &'the host backend')
        call pftc%shiftmap_shifts(xy)
        call assert_true(index(pftc%message(), 'MLX backend') > 0 .and. .not. allocated(xy), device_name(dev)// &
            &': the modes'' shifts are refused on the host backend')
        temps = 1._real32
        call pftc%submit_block(1, 1, [1], temps)
        call assert_true(index(pftc%message(), 'MLX backend') > 0, device_name(dev)//': a block in flight is '// &
            &'refused on the host backend')
        call pftc%collect_block(1, dists, irots)
        call assert_true(index(pftc%message(), 'refused') > 0, device_name(dev)//': a collection without a block '// &
            &'is refused on the host backend')
        call pftc%kill()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': polarft_calc on the host backend left no '// &
            &'device object')
    end subroutine test_polarft_calc

    ! the smallest calculator with its particles and weights memoized; nbad counts the refusals
    subroutine small_map_calc( pftc, nbad )
        type(polarft_calc), intent(inout) :: pftc
        integer,            intent(inout) :: nbad
        complex(real32) :: pft(C_PFTSZ, C_NK)
        real(real32)    :: ctf(C_PFTSZ, C_NK)
        real(real64)    :: w(C_NK, 2)
        integer         :: i, j, k
        call small_calc(pftc, .true., .true., nbad)
        w = 1._real64
        call pftc%set_sigma2_weights(w)
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
        do i = 1, 2
            do k = 1, C_NK
                do j = 1, C_PFTSZ
                    pft(j, k) = cmplx(real(j - i, real32), real(k, real32) / 2._real32, real32)
                    ctf(j, k) = 0.5_real32 + 0.1_real32 * real(j, real32)
                end do
            end do
            call pftc%set_eo(i, i == 1)
            call pftc%set_ptcl_ctfmat(i, ctf)
            call pftc%set_ptcl_pft(i, pft)
            if( len(pftc%message()) > 0 ) nbad = nbad + 1
        end do
        call pftc%memoize_ptcls()
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
    end subroutine small_map_calc

    ! 100 cycles of new_shiftmap, gen_shiftmap, shiftmap_mode and kill_shiftmap on one calculator leave the live
    ! handles and the active memory where a warm cycle left them
    subroutine test_polarft_maps( dev )
        integer, intent(in) :: dev
        type(polarft_calc) :: pftc
        integer(int64)     :: mem0
        integer            :: live0, nbad, i
        write(*,'(a)') 'test_polarft_maps'
        nbad = 0
        call small_map_calc(pftc, nbad)
        call map_cycle(pftc, nbad)
        call mlx_synchronize()
        call mlx_clear_cache()
        live0 = mlx_live_count()
        mem0  = mlx_active_memory()
        do i = 1, NMAPCYCLES
            call map_cycle(pftc, nbad)
        end do
        call mlx_synchronize()
        call mlx_clear_cache()
        call assert_int(0, nbad, device_name(dev)//': polarft_calc: every map cycle was carried out')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': polarft_calc: 100 map cycles leave the live '//&
            &'handles as they were')
        call assert_true(mlx_active_memory() == mem0, device_name(dev)//': polarft_calc: 100 map cycles leave the '//&
            &'active memory as it was')
        call pftc%kill()
    end subroutine test_polarft_maps

    ! one map's cycle: made, the modes of particle 1 against both references read, every map released
    subroutine map_cycle( pftc, nbad )
        type(polarft_calc), intent(inout) :: pftc
        integer,            intent(inout) :: nbad
        real(real32) :: loss(C_NREFS)
        integer      :: irot(C_NREFS), irho(C_NREFS), ialpha(C_NREFS)
        call pftc%new_shiftmap(1, [0._real64, 1._real64], 8, C_NK)
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
        call pftc%gen_shiftmap(1, [1, 2], [1, 1])
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
        call pftc%shiftmap_mode(1, [1._real64, 1._real64], 0._real64, irot, irho, ialpha, loss)
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
        call pftc%kill_shiftmap()
        if( len(pftc%message()) > 0 ) nbad = nbad + 1
    end subroutine map_cycle

    ! ---- the projector -------------------------------------------------------------------------------------------

    ! a volume and its padded projector; full also pads, transforms and expands (the device arrays); nbad counts
    ! the refusals
    subroutine small_projector( vol, vol_pad, full, nbad )
        type(projector), intent(inout) :: vol, vol_pad
        logical,         intent(in)    :: full
        integer,         intent(inout) :: nbad
        real(real32) :: rmat(P_N, P_N, P_N)
        call vol%new([P_N, P_N, P_N], 1._real32)
        if( len(vol%message()) > 0 ) nbad = nbad + 1
        call vol_pad%new([2 * P_N, 2 * P_N, 2 * P_N], 1._real32)
        if( len(vol_pad%message()) > 0 ) nbad = nbad + 1
        if( .not. full ) return
        rmat          = 0._real32
        rmat(2, 3, 1) = 1._real32
        call vol%set_rmat(rmat, .false.)
        call vol%pad_fft(vol_pad)
        call vol_pad%expand_cmat()
        if( len(vol_pad%message()) > 0 .or. .not. vol_pad%is_expanded() ) nbad = nbad + 1
    end subroutine small_projector

    ! the projector's cycles, its refusal of the host backend, and a device state of another type
    subroutine test_projector( dev )
        integer, intent(in) :: dev
        type(projector) :: vol, vol_pad
        integer         :: live0, nbad, i
        integer(int64)  :: mem0, mem1
        write(*,'(a)') 'test_projector'
        nbad  = 0
        live0 = mlx_live_count()
        call small_projector(vol, vol_pad, .true., nbad)
        call assert_true(mlx_live_count() > live0, device_name(dev)//': an expanded projector holds device arrays')
        call vol_pad%kill()
        call vol%kill()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': projector%kill releases them')
        call mlx_synchronize()
        mem0 = mlx_active_memory()
        do i = 1, NCYCLES
            call small_projector(vol, vol_pad, mod(i, FULL_EVERY) == 0, nbad)
            call vol_pad%kill()
            call vol%kill()
        end do
        call mlx_synchronize()
        mem1 = mlx_active_memory()
        call assert_int(0, nbad, device_name(dev)//': projector: every cycle was carried out')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': projector: 1,000 cycles of new and kill leave '// &
            &'the live handles as they were')
        call assert_true(mem1 == mem0, device_name(dev)//': projector: 1,000 cycles of new and kill leave the active '// &
            &'memory as it was')
        ! the toy has no host route: the host backend is refused at new, and no device object is made
        call vol%new([P_N, P_N, P_N], 1._real32, params=parameters(l_mlx=.false.))
        call assert_true(index(vol%message(), 'no host route') > 0, device_name(dev)//': projector%new on the host '// &
            &'backend is refused: the toy has no host route')
        call assert_true(.not. allocated(vol%ws), device_name(dev)//': a refused projector has no device state')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': a refused projector made no device object')
        ! a device state of another type is refused with a message, and kill still releases it
        call small_projector(vol, vol_pad, .true., nbad)
        call vol_pad%ws%kill()
        deallocate(vol_pad%ws)
        allocate(work_stranger :: vol_pad%ws)
        call vol_pad%expand_cmat()
        call assert_true(index(vol_pad%message(), 'not a projector_workspace') > 0, device_name(dev)//': a projector '// &
            &'whose device state has another type refuses with a message')
        call vol_pad%kill()
        call vol%kill()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': projector%kill releases a device state of any type')
    end subroutine test_projector

    ! ---- the reconstructor ---------------------------------------------------------------------------------------

    ! a reconstructor of the small box; full also takes accumulators of a uniform density, closes the accumulation
    ! and applies the operator to a host volume (the device arrays); nbad counts what was refused
    subroutine small_reconstructor( rec, full, nbad )
        type(reconstructor_pcg), intent(inout) :: rec
        logical,                 intent(in)    :: full
        integer,                 intent(inout) :: nbad
        complex(real32)           :: b(R_N + 1, 2 * R_N, 2 * R_N)
        real(real32)              :: d(R_N + 1, 2 * R_N, 2 * R_N), u(R_N, R_N, R_N)
        real(real32), allocatable :: hu(:,:,:)
        call rec%new(R_N)
        if( len(rec%message()) > 0 ) nbad = nbad + 1
        if( .not. full ) return
        b          = cmplx(0._real32, 0._real32, real32)
        b(1, 1, 1) = cmplx(1._real32, 0._real32, real32)
        d          = 1._real32
        u          = 0._real32
        u(2, 3, 1) = 1._real32
        call rec%set_raw_accum(b, d)
        call rec%end_accum(.true.)
        hu = rec%apply_normal(u)
        if( len(rec%message()) > 0 .or. size(hu) /= R_N**3 ) nbad = nbad + 1
    end subroutine small_reconstructor

    ! the reconstructor's cycles, the operator it hands out, and its refusal of the host backend
    subroutine test_reconstructor_pcg( dev )
        integer, intent(in) :: dev
        type(reconstructor_pcg), target      :: rec
        class(device_work),      allocatable :: op
        integer                              :: live0, live1, nbad, i
        integer(int64)                       :: mem0, mem1
        write(*,'(a)') 'test_reconstructor_pcg'
        nbad  = 0
        live0 = mlx_live_count()
        call small_reconstructor(rec, .true., nbad)
        live1 = mlx_live_count()
        call assert_true(live1 > live0, device_name(dev)//': a reconstructor after end_accum holds device arrays')
        ! the operator the engine solves with, opaque: it holds no device object and is let go before the class
        call rec%get_pcg_operator(op)
        call assert_true(allocated(op), device_name(dev)//': reconstructor_pcg%get_pcg_operator hands out its operator '// &
            &'as the opaque device state')
        call assert_int(live1, mlx_live_count(), device_name(dev)//': the operator handed out holds no device object')
        if( allocated(op) )then
            call op%kill()
            deallocate(op)
        endif
        call rec%kill()
        call assert_int(live0, mlx_live_count(), device_name(dev)//': reconstructor_pcg%kill releases the device arrays')
        call mlx_synchronize()
        mem0 = mlx_active_memory()
        do i = 1, NCYCLES
            call small_reconstructor(rec, mod(i, FULL_EVERY) == 0, nbad)
            call rec%kill()
        end do
        call mlx_synchronize()
        mem1 = mlx_active_memory()
        call assert_int(0, nbad, device_name(dev)//': reconstructor_pcg: every cycle was carried out')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': reconstructor_pcg: 1,000 cycles of new and kill '// &
            &'leave the live handles as they were')
        call assert_true(mem1 == mem0, device_name(dev)//': reconstructor_pcg: 1,000 cycles of new and kill leave the '// &
            &'active memory as it was')
        ! the toy has no host route: the host backend is refused at new, no device object is made, and no operator
        ! is handed out
        call rec%new(R_N, params=parameters(l_mlx=.false.))
        call assert_true(index(rec%message(), 'new: refused: the toy has no host route') > 0, device_name(dev)// &
            &': reconstructor_pcg%new on the host backend is refused: the toy has no host route')
        call assert_int(live0, mlx_live_count(), device_name(dev)//': a refused reconstructor made no device object')
        call rec%get_pcg_operator(op)
        call assert_true(.not. allocated(op), device_name(dev)//': a refused reconstructor hands out no operator')
        call assert_true(index(rec%message(), 'get_pcg_operator: refused: the toy has no host route') > 0, &
            &device_name(dev)//': and says why: '//rec%message())
        call rec%kill()
    end subroutine test_reconstructor_pcg

end module mlxf_toy_seam_tester
