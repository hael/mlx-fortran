!@descr: the off-state program of the toys: what a build without MLX runs, built without USE_MLX and without the library
! It imports the toys' host modules only. It fills the polar host route's table on the fixture of sub-suite
! polarft_host and writes its lines (scripts/check_toy_offstate.sh compares them with mlxf_test_exec's), checks that
! a team of four fills the same bytes, writes the neighbourhood tables (the cone and the state fill) of the
! same fixture on the host route, asks each toy class for the MLX backend: every one must refuse with "built
! without MLX", the neighbourhood driver reporting its calculator's refusal, and asks the host backend's
! calculator for a shift map, which it refuses. Exit status 1 when a check fails.
program mlxf_offstate_exec
use, intrinsic :: iso_fortran_env, only: int32, real32, real64
use mlxf_test_defs,             only: PH_PFTSZ, PH_CONES, NEIGH_ORDERS, parameters, polarft_host_fixture, &
                                      polarft_host_table, polarft_neigh_table
use mlxf_toy_polarft_calc,      only: polarft_calc
use mlxf_toy_projector,         only: projector
use mlxf_toy_reconstructor_pcg, only: reconstructor_pcg
use mlxf_polarft_host_fixture,  only: make_polarft_host_fixture, fill_polarft_host_table, write_polarft_host_table, &
                                      fill_polarft_neigh_table, write_polarft_neigh_table
implicit none
integer, parameter         :: SEEDS(3) = [1, 2, 3]
integer, parameter         :: NTEAM    = 4
type(polarft_host_fixture) :: fx
type(polarft_host_table)   :: one, team
type(polarft_neigh_table)  :: nt
type(polarft_calc)         :: pftc
type(projector)            :: vol
type(reconstructor_pcg)    :: rec
real(real32)               :: u(4, 4, 4)
real(real32), allocatable  :: hu(:,:,:)
integer                    :: is, nfailed
nfailed = 0
write(*,'(a)') 'mlxf_offstate_exec: built without USE_MLX and without the library'
! the polar host route: the table of one thread, written, and that of a team
do is = 1, size(SEEDS)
    fx       = make_polarft_host_fixture(SEEDS(is))
    one%nthr = 1
    call fill_polarft_host_table(fx, one)
    call check(len(one%msg) == 0, 'the host route fills the table: '//one%msg)
    if( len(one%msg) > 0 ) cycle
    call write_polarft_host_table(fx, one)
    team%nthr = NTEAM
    call fill_polarft_host_table(fx, team)
    call check(len(team%msg) == 0, 'a team of four fills the table: '//team%msg)
    if( len(team%msg) > 0 ) cycle
    call check(all(team%order == one%order) .and. all(team%irots == one%irots) .and. &
        &all(transfer(team%dists, [0_int32]) == transfer(one%dists, [0_int32])), &
        &'a team of four fills the table of one thread, byte for byte')
    ! the neighbourhood tables of the host route: the cone of 30 degrees and the state fill, SIMPLE's block order
    nt       = polarft_neigh_table()
    nt%mode  = 'geom'
    nt%cone  = PH_CONES(1)
    nt%order = NEIGH_ORDERS%simple
    call fill_polarft_neigh_table(fx, nt)
    call check(len(nt%msg) == 0, 'the host route fills the cone table: '//nt%msg)
    if( len(nt%msg) == 0 ) call write_polarft_neigh_table(fx, nt)
    nt       = polarft_neigh_table()
    nt%mode  = 'state'
    nt%order = NEIGH_ORDERS%simple
    call fill_polarft_neigh_table(fx, nt)
    call check(len(nt%msg) == 0, 'the host route fills the state table: '//nt%msg)
    if( len(nt%msg) == 0 ) call write_polarft_neigh_table(fx, nt)
end do
! a neighbourhood fill on the MLX backend reports its calculator's refusal
nt       = polarft_neigh_table()
nt%l_mlx = .true.
call fill_polarft_neigh_table(fx, nt)
call check(index(nt%msg, 'built without MLX') > 0, 'eul_prob_tab_neigh reports the calculator''s refusal of the '// &
    &'MLX backend: '//nt%msg)
! the MLX backend is refused by every class, with the stub's message
call pftc%new(parameters(pftsz=PH_PFTSZ, l_mlx=.true.), 2, [1, 2], [1, 2])
call check(index(pftc%message(), 'built without MLX') > 0, 'polarft_calc refuses the MLX backend: '//pftc%message())
call pftc%kill()
! the host backend has no shift maps: a calculator on it refuses them
call pftc%new(parameters(pftsz=PH_PFTSZ, l_mlx=.false.), 2, [1, 2], [1, 2])
call pftc%new_shiftmap(1, [0._real64, 1._real64], 8, 2)
call check(index(pftc%message(), 'shift maps run on the MLX backend only') > 0, &
    &'polarft_calc on the host backend refuses a shift map: '//pftc%message())
call pftc%kill()
call vol%new([4, 4, 4], 1._real32)
call check(index(vol%message(), 'built without MLX') > 0, 'projector refuses the MLX backend: '//vol%message())
call vol%new([4, 4, 4], 1._real32, params=parameters(l_mlx=.false.))
call check(index(vol%message(), 'no host route') > 0, 'projector has no host route: '//vol%message())
call vol%kill()
call rec%new(4)
call check(index(rec%message(), 'built without MLX') > 0, 'reconstructor_pcg refuses the MLX backend: '//rec%message())
call rec%new(4, params=parameters(l_mlx=.false.))
call check(index(rec%message(), 'no host route') > 0, 'reconstructor_pcg has no host route: '//rec%message())
u  = 1._real32
hu = rec%apply_normal(u)
call check(size(hu) == 0 .and. index(rec%message(), 'apply_normal: refused') > 0, &
    &'reconstructor_pcg applies no operator without a reconstructor: '//rec%message())
call rec%kill()
if( nfailed > 0 )then
    write(*,'(a,i0,a)') 'mlxf_offstate_exec: FAILED (', nfailed, ' checks)'
    error stop 1
endif
write(*,'(a)') 'mlxf_offstate_exec: passed'

contains

    subroutine check( ok, what )
        logical,          intent(in) :: ok
        character(len=*), intent(in) :: what
        if( ok )then
            write(*,'(a)') 'ok:   '//what
        else
            write(*,'(a)') 'FAIL: '//what
            nfailed = nfailed + 1
        endif
    end subroutine check

end program mlxf_offstate_exec
