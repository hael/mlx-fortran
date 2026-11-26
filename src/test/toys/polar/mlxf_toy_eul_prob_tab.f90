!@descr: the toy table driver (test only): a miniature of SIMPLE's eul_prob_tab that fills the dense table through the polar calculator
! The strategy's loop over a range of particles, as SIMPLE's fill_tab_range walks it: the range is cut into
! blocks of one half, each block is scored against every reference by the calculator, and its particles'
! candidate pairs are then read on a shift map. The fill has two shapes and selects once (the parameters'
! l_mlx): on the host backend the team scores the blocks from inside a parallel region, one block a thread, as
! SIMPLE does; on the MLX backend one thread queues the blocks, one or two in flight, from outside any region.
! The driver owns what SIMPLE's owns: the particles, their temperatures, the scope of the keyed draws and the
! batch's rows. It holds no MLX state and imports no MLX name: every device call goes through the calculator.
! scripts/toy_mirror.txt lists each procedure as mirrored or as an addition.
module mlxf_toy_eul_prob_tab
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf_test_defs,        only: SHIFTMAP_WINDOW, PFTC_BLOCK_NB, parameters, polar_map_results
use mlxf_toy_polarft_calc, only: polarft_calc, keyed_variate
implicit none

public :: eul_prob_tab
private

! SIMPLE's members under SIMPLE's names, for the members the toy has: the particles (pinds), their inverse
! temperatures (temps), the batch's rows (batch_dists, batch_irots; batch_rows the full rows when kept). The
! calculator and the parameters stand for SIMPLE's builder and parameters pointers. The rest serves the
! additions: the keys of the draws (the seed and each reference's full index), the candidates of the maps and
! their width cutoffs, the fixture's map, the fill's options and stages, the order of the batch (porder: the
! even half's particles, then the odd half's), the maps' results, the fill's seconds, the last refusal.
type :: eul_prob_tab
    private
    type(polarft_calc), pointer   :: pftc => null()
    type(parameters)              :: params
    integer,          allocatable :: pinds(:)
    real(real32),     allocatable :: temps(:)
    integer                       :: nptcls     = 0
    integer                       :: nrefs      = 0
    real(real32),     allocatable :: batch_dists(:,:)
    integer,          allocatable :: batch_irots(:,:)
    real(real32),     allocatable :: batch_rows(:,:,:)
    integer                       :: rnd_seed   = 0
    integer,          allocatable :: ref_full(:)
    integer,          allocatable :: cands(:,:)
    real(real32),     allocatable :: width_cutoff(:,:)
    integer                       :: imap       = 0
    real(real64)                  :: prior_w    = 0._real64
    integer                       :: block_nb   = PFTC_BLOCK_NB
    integer                       :: nslots     = 1
    logical                       :: l_rows     = .false.
    logical                       :: l_profile  = .false.
    logical                       :: l_dense    = .true.
    logical                       :: l_maps     = .false.
    logical                       :: l_keys     = .false.
    integer,          allocatable :: porder(:)
    type(polar_map_results)       :: batch_maps
    real(real64)                  :: fill_s(4)  = 0._real64
    character(len=:), allocatable :: msg
    logical                       :: existence  = .false.
  contains
    procedure :: new_pipeline
    procedure :: fill_tab_range
    procedure :: kill
    procedure :: set_draw_keys
    procedure :: set_temps
    procedure :: set_candidates
    procedure :: set_width_cutoffs
    procedure :: use_shiftmap
    procedure :: set_fill_options
    procedure :: set_fill_stages
    procedure :: batch_entries
    procedure :: batch_full_rows
    procedure :: batch_map_results
    procedure :: fill_seconds
    procedure :: message
end type eul_prob_tab

contains

    ! the driver of the particles pinds (project indices, all held by the calculator) against every reference of
    ! the calculator, whose reference bins are made here unless they are current; a refusal (message) leaves the
    ! driver not existing
    subroutine new_pipeline( self, params, pftc, pinds )
        class(eul_prob_tab),        intent(inout) :: self
        type(parameters),           intent(in)    :: params
        type(polarft_calc), target, intent(inout) :: pftc
        integer,                    intent(in)    :: pinds(:)
        integer :: r
        call self%kill
        if( size(pinds) < 1 )then
            self%msg = 'eul_prob_tab%new_pipeline: refused: no particles'
            return
        endif
        if( params%nthr < 1 )then
            self%msg = 'eul_prob_tab%new_pipeline: refused: the team has at least one thread'
            return
        endif
        if( .not. pftc%ref_bins_current() )then
            call pftc%memoize_ref_bins
            if( len(pftc%message()) > 0 )then
                self%msg = pftc%message()
                return
            endif
        endif
        self%pftc      => pftc
        self%params    = params
        self%pinds     = pinds
        self%nptcls    = size(pinds)
        self%nrefs     = pftc%get_nrefs()
        self%ref_full  = [(r, r = 1, self%nrefs)]
        self%existence = .true.
    end subroutine new_pipeline

    ! idempotent: the driver forgets its calculator and releases its arrays
    subroutine kill( self )
        class(eul_prob_tab), intent(inout) :: self
        self%pftc => null()
        if( allocated(self%pinds) ) deallocate(self%pinds)
        if( allocated(self%temps) ) deallocate(self%temps)
        if( allocated(self%batch_dists) ) deallocate(self%batch_dists)
        if( allocated(self%batch_irots) ) deallocate(self%batch_irots)
        if( allocated(self%batch_rows) ) deallocate(self%batch_rows)
        if( allocated(self%ref_full) ) deallocate(self%ref_full)
        if( allocated(self%cands) ) deallocate(self%cands)
        if( allocated(self%width_cutoff) ) deallocate(self%width_cutoff)
        if( allocated(self%porder) ) deallocate(self%porder)
        call drop_maps(self%batch_maps)
        self%nptcls    = 0
        self%nrefs     = 0
        self%rnd_seed  = 0
        self%imap      = 0
        self%prior_w   = 0._real64
        self%block_nb  = PFTC_BLOCK_NB
        self%nslots    = 1
        self%l_rows    = .false.
        self%l_profile = .false.
        self%l_dense   = .true.
        self%l_maps    = .false.
        self%l_keys    = .false.
        self%fill_s    = 0._real64
        self%msg       = ''
        self%existence = .false.
    end subroutine kill

    subroutine drop_maps( res )
        type(polar_map_results), intent(inout) :: res
        if( allocated(res%loss) ) deallocate(res%loss)
        if( allocated(res%sdev) ) deallocate(res%sdev)
        if( allocated(res%logz) ) deallocate(res%logz)
        if( allocated(res%irot) ) deallocate(res%irot)
        if( allocated(res%irho) ) deallocate(res%irho)
        if( allocated(res%ialpha) ) deallocate(res%ialpha)
        if( allocated(res%maps) ) deallocate(res%maps)
    end subroutine drop_maps

    ! the keys of the draws: a pair's variate is keyed by seed, the particle's project index and the reference's
    ! full index ref_full(iref), never by its place in a block
    subroutine set_draw_keys( self, seed, ref_full )
        class(eul_prob_tab), intent(inout) :: self
        integer,             intent(in)    :: seed
        integer,             intent(in)    :: ref_full(:)
        if( .not. self%existence )then
            self%msg = 'eul_prob_tab%set_draw_keys: refused: no driver (new_pipeline)'
            return
        endif
        if( size(ref_full) /= self%nrefs )then
            self%msg = 'eul_prob_tab%set_draw_keys: refused: one full index per reference'
            return
        endif
        self%msg      = ''
        self%rnd_seed = seed
        self%ref_full = ref_full
        self%l_keys   = .true.
        ! the host backend's kernel draws inside the calculator, as SIMPLE's does from its scope
        if( .not. self%params%l_mlx )then
            call self%pftc%set_draw_keys(seed, ref_full)
            self%msg = self%pftc%message()
        endif
    end subroutine set_draw_keys

    ! each particle's inverse temperature of the dense draw, in the order of pinds
    subroutine set_temps( self, temps )
        class(eul_prob_tab), intent(inout) :: self
        real(real32),        intent(in)    :: temps(:)
        if( .not. self%existence .or. size(temps) /= self%nptcls )then
            self%msg = 'eul_prob_tab%set_temps: refused: one temperature per particle of an existing driver'
            return
        endif
        self%msg   = ''
        self%temps = temps
    end subroutine set_temps

    ! each particle's candidate references for the shift maps (candidates, particles in the order of pinds), the
    ! same number for each; the fill reads their maps from then on
    subroutine set_candidates( self, cands )
        class(eul_prob_tab), intent(inout) :: self
        integer,             intent(in)    :: cands(:,:)
        if( .not. self%existence )then
            self%msg = 'eul_prob_tab%set_candidates: refused: no driver (new_pipeline)'
            return
        endif
        if( size(cands, 1) < 1 .or. size(cands, 2) /= self%nptcls )then
            self%msg = 'eul_prob_tab%set_candidates: refused: a candidate at least for every particle'
            return
        endif
        self%msg    = ''
        self%cands  = cands
        self%l_maps = .true.
        if( allocated(self%width_cutoff) ) deallocate(self%width_cutoff)
    end subroutine set_candidates

    ! per candidate pair the loss above which its width is skipped (candidates, particles in the order of pinds)
    subroutine set_width_cutoffs( self, width_cutoff )
        class(eul_prob_tab), intent(inout) :: self
        real(real32),        intent(in)    :: width_cutoff(:,:)
        if( .not. allocated(self%cands) )then
            self%msg = 'eul_prob_tab%set_width_cutoffs: refused: no candidates (set_candidates)'
            return
        endif
        if( any(shape(width_cutoff) /= shape(self%cands)) )then
            self%msg = 'eul_prob_tab%set_width_cutoffs: refused: one cutoff per candidate pair'
            return
        endif
        self%msg          = ''
        self%width_cutoff = width_cutoff
    end subroutine set_width_cutoffs

    ! the fill reads every particle's candidates on the calculator's map imap, made beforehand, under a prior of
    ! weight prior_w; imap 0 returns to the two coarse maps the fill sets up itself
    subroutine use_shiftmap( self, imap, prior_w )
        class(eul_prob_tab), intent(inout) :: self
        integer,             intent(in)    :: imap
        real(real64),        intent(in)    :: prior_w
        self%msg     = ''
        self%imap    = imap
        self%prior_w = prior_w
    end subroutine use_shiftmap

    ! how the fill runs: the particles of a block (one call of the scorer), one block or two in flight, the
    ! full rows kept, the calculator's stages profiled
    subroutine set_fill_options( self, block_nb, nslots, rows, profile )
        class(eul_prob_tab), intent(inout) :: self
        integer,             intent(in)    :: block_nb, nslots
        logical,             intent(in)    :: rows, profile
        if( block_nb < 1 .or. nslots < 1 .or. nslots > 2 )then
            self%msg = 'eul_prob_tab%set_fill_options: refused: a block has a particle at least, and one or two are in flight'
            return
        endif
        self%msg       = ''
        self%block_nb  = block_nb
        self%nslots    = nslots
        self%l_rows    = rows
        self%l_profile = profile
    end subroutine set_fill_options

    ! which stages the fill runs: the dense score of each block, the shift maps of its candidates (which need
    ! set_candidates)
    subroutine set_fill_stages( self, dense, maps )
        class(eul_prob_tab), intent(inout) :: self
        logical,             intent(in)    :: dense, maps
        if( maps .and. .not. allocated(self%cands) )then
            self%msg = 'eul_prob_tab%set_fill_stages: refused: no candidates (set_candidates)'
            return
        endif
        self%msg     = ''
        self%l_dense = dense
        self%l_maps  = maps
    end subroutine set_fill_stages

    ! seconds of a monotonic clock
    real(real64) function clock_s()
        integer(int64) :: count, rate
        call system_clock(count, rate)
        clock_s = real(count, real64) / real(rate, real64)
    end function clock_s

    ! the particles i_first..i_last of pinds: cut into blocks of one half, each block scored against every
    ! reference (its rows kept for the batch), then its particles' candidates read on the shift map. On the host
    ! backend the team scores the blocks in a parallel region; on the MLX backend one thread queues them and, with
    ! two blocks in flight, queues a block before the one before it is collected. A refusal (message) ends the fill.
    subroutine fill_tab_range( self, i_first, i_last )
        class(eul_prob_tab), intent(inout) :: self
        integer,             intent(in)    :: i_first, i_last
        integer, allocatable :: blocks(:,:)
        real(real64)         :: prior_w, prior_map
        integer              :: nblocks, ib, n, ncand, imap, kscreen
        if( .not. self%existence )then
            self%msg = 'eul_prob_tab%fill_tab_range: refused: no driver (new_pipeline)'
            return
        endif
        if( i_first < 1 .or. i_last > self%nptcls .or. i_last < i_first )then
            self%msg = 'eul_prob_tab%fill_tab_range: refused: the range is not in the driver''s particles'
        else if( self%l_dense .and. .not. allocated(self%temps) )then
            self%msg = 'eul_prob_tab%fill_tab_range: refused: no temperatures (set_temps)'
        else if( self%l_dense .and. .not. self%l_keys )then
            self%msg = 'eul_prob_tab%fill_tab_range: refused: no keys of the draws (set_draw_keys)'
        else if( .not. (self%l_dense .or. self%l_maps) )then
            self%msg = 'eul_prob_tab%fill_tab_range: refused: no stage to run (set_fill_stages)'
        else
            self%msg = ''
        endif
        if( len(self%msg) > 0 ) return
        n = i_last - i_first + 1
        if( allocated(self%batch_dists) ) deallocate(self%batch_dists)
        if( allocated(self%batch_irots) ) deallocate(self%batch_irots)
        if( allocated(self%batch_rows) ) deallocate(self%batch_rows)
        call drop_maps(self%batch_maps)
        if( self%l_dense )then
            allocate(self%batch_dists(self%nrefs, n), self%batch_irots(self%nrefs, n))
            if( self%l_rows ) allocate(self%batch_rows(2 * self%pftc%get_pftsz(), self%nrefs, n))
            call self%pftc%set_block_options(self%l_rows, self%l_profile)
        endif
        ! the map of the fill: the fixture's, or the window of the two coarse maps set up as SIMPLE sets them up
        imap      = self%imap
        prior_map = self%prior_w
        kscreen   = 0
        if( self%l_maps )then
            if( imap == 0 )then
                call self%pftc%setup_shiftmaps(real(self%params%shift_sigma, real64) / real(self%params%smpd, real64), &
                    &real(min(3. * self%params%shift_sigma / self%params%smpd, 0.5 * real(self%params%box) - 1.), real64), &
                    &real(self%params%trs, real64), prior_w, kscreen)
                imap      = SHIFTMAP_WINDOW
                prior_map = 0._real64
            else
                kscreen = self%pftc%shiftmap_kstop(imap)
            endif
            if( len(self%pftc%message()) > 0 .or. kscreen == 0 )then
                self%msg = 'eul_prob_tab%fill_tab_range: refused: no shift map: '//self%pftc%message()
                return
            endif
            ncand = size(self%cands, 1)
            allocate(self%batch_maps%loss(ncand, n), self%batch_maps%sdev(ncand, n), self%batch_maps%irot(ncand, n), &
                &self%batch_maps%irho(ncand, n), self%batch_maps%ialpha(ncand, n))
        endif
        call cut_blocks
        ! the backend is selected once
        if( .not. self%params%l_mlx )then
            call fill_host
            return
        endif
        do ib = 1, nblocks
            if( self%l_dense ) call process_block(blocks(1, ib), blocks(2, ib), slot_of(ib))
            if( len(self%msg) > 0 ) return
            if( self%nslots == 2 .and. ib > 1 ) call finish_block(ib - 1)
            if( self%nslots == 1 ) call finish_block(ib)
            if( len(self%msg) > 0 ) return
        end do
        if( self%nslots == 2 ) call finish_block(nblocks)

      contains

        ! the range's particles in the batch's order, the even half first, and the blocks of at most block_nb
        ! particles of one half
        subroutine cut_blocks
            integer :: i, j, half, j0, nhalf(2)
            if( allocated(self%porder) ) deallocate(self%porder)
            allocate(self%porder(n), blocks(2, n))
            j       = 0
            nblocks = 0
            do half = 1, 2
                j0 = j
                do i = i_first, i_last
                    if( self%pftc%ptcl_iseven(self%pinds(i)) .neqv. (half == 1) ) cycle
                    j              = j + 1
                    self%porder(j) = i
                end do
                nhalf(half) = j - j0
                do i = 1, nhalf(half), self%block_nb
                    nblocks            = nblocks + 1
                    blocks(:, nblocks) = [j0 + i, j0 + min(i + self%block_nb - 1, nhalf(half))]
                end do
            end do
        end subroutine cut_blocks

        ! the host backend's fill, SIMPLE's: every block is scored whole by one thread of the team, with that
        ! thread's work, writing only its particles' columns; every draw is keyed on the particle and the
        ! reference, so the thread and the block a pair meets change nothing
        subroutine fill_host
            integer, allocatable :: irefs_tab(:)
            real(real64)         :: t0
            integer              :: r, kb
            if( .not. self%l_dense ) return
            if( self%block_nb > PFTC_BLOCK_NB )then
                self%msg = 'eul_prob_tab%fill_tab_range: refused: on the host backend a block holds at most '// &
                    &'PFTC_BLOCK_NB particles (set_fill_options)'
                return
            endif
            ! what a block could not say from inside the region is asked before it
            call self%pftc%check_block_work(self%params%nthr)
            self%msg = self%pftc%message()
            if( len(self%msg) > 0 ) return
            irefs_tab = [(r, r = 1, self%nrefs)]
            t0        = clock_s()
            !$omp parallel do num_threads(self%params%nthr) default(shared) private(kb) schedule(dynamic) proc_bind(close)
            do kb = 1, nblocks
                call process_block_host(blocks(1, kb), blocks(2, kb), irefs_tab)
            end do
            !$omp end parallel do
            self%fill_s(2) = self%fill_s(2) + (clock_s() - t0)
        end subroutine fill_host

        ! one block on the calling thread: its particles and temperatures, the kernel, its rows when kept; no
        ! allocation
        subroutine process_block_host( j0, j1, irefs_tab )
            integer, intent(in) :: j0, j1
            integer, intent(in) :: irefs_tab(:)
            real(real32) :: temps_b(PFTC_BLOCK_NB)
            integer      :: iptcls_b(PFTC_BLOCK_NB), nb, b
            nb = j1 - j0 + 1
            do b = 1, nb
                iptcls_b(b) = self%pinds(self%porder(j0 + b - 1))
                temps_b(b)  = self%temps(self%porder(j0 + b - 1))
            end do
            call self%pftc%score_block_posterior(nb, iptcls_b(1:nb), self%nrefs, irefs_tab, temps_b(1:nb), &
                &self%batch_dists(:, j0:j1), self%batch_irots(:, j0:j1))
            if( self%l_rows ) call self%pftc%copy_block_rows(self%batch_rows(:, :, j0:j1))
        end subroutine process_block_host

        ! the slot of block kb: with two in flight they alternate
        pure integer function slot_of( kb )
            integer, intent(in) :: kb
            slot_of = 1
            if( self%nslots == 2 ) slot_of = mod(kb - 1, 2) + 1
        end function slot_of

        ! a block's dense score queued: its particles, their temperatures, and each pair's keyed variate, made
        ! by the host team
        subroutine process_block( j0, j1, slot )
            integer, intent(in) :: j0, j1, slot
            real(real32), allocatable :: u(:,:), temps_b(:)
            integer,      allocatable :: iptcls_b(:)
            real(real64)              :: t0
            integer                   :: b, r, nb
            nb       = j1 - j0 + 1
            iptcls_b = self%pinds(self%porder(j0:j1))
            temps_b  = self%temps(self%porder(j0:j1))
            t0       = clock_s()
            allocate(u(self%nrefs, nb))
            !$omp parallel do num_threads(self%params%nthr) default(shared) private(b, r) schedule(static) proc_bind(close)
            do b = 1, nb
                do r = 1, self%nrefs
                    u(r, b) = real(keyed_variate(self%rnd_seed, iptcls_b(b), self%ref_full(r)), real32)
                end do
            end do
            !$omp end parallel do
            self%fill_s(1) = self%fill_s(1) + (clock_s() - t0)
            t0 = clock_s()
            call self%pftc%set_block_variates(u)
            call self%pftc%submit_block(slot, nb, iptcls_b, temps_b)
            self%fill_s(2) = self%fill_s(2) + (clock_s() - t0)
            self%msg = self%pftc%message()
        end subroutine process_block

        ! block kb finished: its dense entries collected into the batch's rows, then its particles' maps read
        subroutine finish_block( kb )
            integer, intent(in) :: kb
            real(real32), allocatable :: rows(:,:,:)
            real(real64)              :: t0
            integer                   :: j0, j1
            j0 = blocks(1, kb)
            j1 = blocks(2, kb)
            if( self%l_dense )then
                t0 = clock_s()
                call self%pftc%collect_block(slot_of(kb), self%batch_dists(:, j0:j1), self%batch_irots(:, j0:j1))
                self%fill_s(3) = self%fill_s(3) + (clock_s() - t0)
                self%msg = self%pftc%message()
                if( len(self%msg) > 0 ) return
                if( self%l_rows )then
                    call self%pftc%block_rows(rows)
                    if( allocated(rows) ) self%batch_rows(:, :, j0:j1) = rows
                endif
            endif
            if( self%l_maps ) call finish_particle_map(j0, j1)
        end subroutine finish_block

        ! the shift maps of a block's particles: every particle's candidates in turn, at the tempered temperature
        ! prob_beta times the particle's physical one over the map's band, the widths at the physical one
        subroutine finish_particle_map( j0, j1 )
            integer, intent(in) :: j0, j1
            real(real64), allocatable :: temp(:), temp_phys(:)
            real(real32), allocatable :: loss(:), sdev(:), logz(:), cut(:)
            integer,      allocatable :: iref(:), iptcl(:), irot(:), irho(:), ialpha(:)
            real(real64)              :: t0, temp_s
            real(real32)              :: tphys
            integer                   :: nb, np, b, c, p, i
            t0 = clock_s()
            nb = j1 - j0 + 1
            np = nb * ncand
            allocate(iref(np), iptcl(np), temp(np), temp_phys(np), irot(np), irho(np), ialpha(np), loss(np), sdev(np))
            if( allocated(self%width_cutoff) ) allocate(cut(np))
            do b = 1, nb
                i      = self%porder(j0 + b - 1)
                tphys  = real(acos(-1._real64) * self%pftc%wsqsum_ptcl_band(self%pinds(i), kscreen) / &
                    &(2._real64 * real(self%pftc%get_pftsz(), real64)), real32)
                temp_s = self%params%prob_beta * real(tphys, real64)
                do c = 1, ncand
                    p            = (b - 1) * ncand + c
                    iref(p)      = self%cands(c, i)
                    iptcl(p)     = self%pinds(i)
                    temp(p)      = temp_s
                    temp_phys(p) = temp_s / self%params%prob_beta
                    if( allocated(cut) ) cut(p) = self%width_cutoff(c, i)
                end do
            end do
            call self%pftc%gen_shiftmap(imap, iref, iptcl)
            self%msg = self%pftc%message()
            if( len(self%msg) > 0 ) return
            if( allocated(cut) )then
                call self%pftc%shiftmap_mode(imap, temp, prior_map, irot, irho, ialpha, loss, temp_phys=temp_phys, &
                    &sdev=sdev, width_cutoff=cut)
            else
                call self%pftc%shiftmap_mode(imap, temp, prior_map, irot, irho, ialpha, loss, temp_phys=temp_phys, &
                    &sdev=sdev)
            endif
            self%msg = self%pftc%message()
            if( len(self%msg) > 0 ) return
            self%batch_maps%loss(:, j0:j1)   = reshape(loss, [ncand, nb])
            self%batch_maps%sdev(:, j0:j1)   = reshape(sdev, [ncand, nb])
            self%batch_maps%irot(:, j0:j1)   = reshape(irot, [ncand, nb])
            self%batch_maps%irho(:, j0:j1)   = reshape(irho, [ncand, nb])
            self%batch_maps%ialpha(:, j0:j1) = reshape(ialpha, [ncand, nb])
            call self%pftc%shiftmap_evidence(logz)
            if( allocated(logz) )then
                if( .not. allocated(self%batch_maps%logz) ) allocate(self%batch_maps%logz(ncand, n))
                self%batch_maps%logz(:, j0:j1) = reshape(logz, [ncand, nb])
            endif
            self%fill_s(4) = self%fill_s(4) + (clock_s() - t0)
        end subroutine finish_particle_map

    end subroutine fill_tab_range

    ! hands over the last fill's dense entries (references, particles in the batch's order) and that order:
    ! order(j) is the place in pinds of the particle of column j, the even half's particles first
    subroutine batch_entries( self, dists, irots, order )
        class(eul_prob_tab),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: dists(:,:)
        integer,      allocatable, intent(out)   :: irots(:,:)
        integer,      allocatable, intent(out)   :: order(:)
        self%msg = ''
        if( allocated(self%batch_dists) ) call move_alloc(self%batch_dists, dists)
        if( allocated(self%batch_irots) ) call move_alloc(self%batch_irots, irots)
        if( allocated(self%porder) ) order = self%porder
    end subroutine batch_entries

    ! hands over the last fill's full rows (rotations, references, particles in the batch's order), when kept
    subroutine batch_full_rows( self, rows )
        class(eul_prob_tab),       intent(inout) :: self
        real(real32), allocatable, intent(out)   :: rows(:,:,:)
        self%msg = ''
        if( allocated(self%batch_rows) ) call move_alloc(self%batch_rows, rows)
    end subroutine batch_full_rows

    ! hands over the last fill's map results per (candidate, particle in the batch's order)
    subroutine batch_map_results( self, res )
        class(eul_prob_tab),     intent(inout) :: self
        type(polar_map_results), intent(out)   :: res
        self%msg = ''
        if( allocated(self%batch_maps%loss) ) call move_alloc(self%batch_maps%loss, res%loss)
        if( allocated(self%batch_maps%sdev) ) call move_alloc(self%batch_maps%sdev, res%sdev)
        if( allocated(self%batch_maps%logz) ) call move_alloc(self%batch_maps%logz, res%logz)
        if( allocated(self%batch_maps%irot) ) call move_alloc(self%batch_maps%irot, res%irot)
        if( allocated(self%batch_maps%irho) ) call move_alloc(self%batch_maps%irho, res%irho)
        if( allocated(self%batch_maps%ialpha) ) call move_alloc(self%batch_maps%ialpha, res%ialpha)
    end subroutine batch_map_results

    ! the fills' accumulated host seconds: the variates, the submissions, the collections (with their waits),
    ! the maps
    pure function fill_seconds( self ) result(t)
        class(eul_prob_tab), intent(in) :: self
        real(real64) :: t(4)
        t = self%fill_s
    end function fill_seconds

    ! the reason the last call was refused, or an empty string when it was carried out
    pure function message( self ) result(msg)
        class(eul_prob_tab), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

end module mlxf_toy_eul_prob_tab
