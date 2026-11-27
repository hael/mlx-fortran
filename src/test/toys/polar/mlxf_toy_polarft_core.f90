!@descr: the toy polar calculator's core: new, kill, the particles' halves, the shell weights, the tile plan and tail, the message
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_core
use mlxf_toy_projector_pft_batch, only: fproject_polar_batch_opt
implicit none

contains

    module subroutine new( self, params, nrefs, pfromto, kfromto )
        class(polarft_calc), intent(inout) :: self
        type(parameters),    intent(in)    :: params
        integer,             intent(in)    :: nrefs
        integer,             intent(in)    :: pfromto(2), kfromto(2)
        real(real32) :: dang, ang
        integer      :: i, irot, k, st
        call self%kill
        if( params%pftsz < 2 .or. mod(params%pftsz, 2) /= 0 )then
            self%msg = 'polarft_calc%new: refused: pftsz must be even and at least 2'
        else if( nrefs < 1 )then
            self%msg = 'polarft_calc%new: refused: nrefs must be at least 1'
        else if( pfromto(1) < 1 .or. pfromto(2) < pfromto(1) )then
            self%msg = 'polarft_calc%new: refused: pfromto must be an ascending range of positive indices'
        else if( kfromto(1) < 1 .or. kfromto(2) < kfromto(1) )then
            self%msg = 'polarft_calc%new: refused: kfromto must be an ascending range of positive shells'
        else if( .not. params%l_mlx .and. params%nthr < 1 )then
            self%msg = 'polarft_calc%new: refused: the host backend''s team has at least one thread'
        endif
        if( len(self%msg) > 0 ) return
        ! the backend is chosen here: the MLX one makes the device state, and a build without MLX refuses it
        self%l_mlx = params%l_mlx
        if( self%l_mlx )then
            call new_mlx(self, st)
            if( st /= 0 )then
                self%l_mlx = .false.
                return
            endif
        endif
        self%pfromto = pfromto
        self%kfromto = kfromto
        self%nk      = kfromto(2) - kfromto(1) + 1
        self%nptcls  = pfromto(2) - pfromto(1) + 1
        self%nrefs   = nrefs
        self%pftsz   = params%pftsz
        self%nrots   = 2 * params%pftsz
        allocate(self%pinds(pfromto(1):pfromto(2)))
        self%pinds = [(i, i = 1, self%nptcls)]
        call alloc_ptcls(self)
        allocate(self%ft_ref_terms(2 * self%nk, self%pftsz+1, nrefs, N_REF_PARITIES), &
            &self%sigma2_wk(kfromto(1):kfromto(2), 2), self%sigma2_wk8(kfromto(1):kfromto(2), 2))
        self%ft_ref_terms = cmplx(0._real32, 0._real32, real32)
        self%sigma2_wk  = 0._real32
        self%sigma2_wk8 = 0._real64
        self%ldim       = [params%box, params%box, 1]
        self%nspace     = params%nspace
        self%nstates    = params%nstates
        self%nthr       = params%nthr
        ! the host backend's block kernel works in its team's own arrays, as SIMPLE's
        if( .not. self%l_mlx ) call new_block_work(self, self%nthr)
        ! SIMPLE's polar coordinates in single precision: h = sin(a) k, k = -cos(a) k
        allocate(self%polar(2, kfromto(1):kfromto(2), self%nrots))
        dang = 2._real32 * acos(-1._real32) / real(self%nrots, real32)
        do irot = 1, self%nrots
            ang = real(irot - 1, real32) * dang
            do k = kfromto(1), kfromto(2)
                self%polar(1, k, irot) =  sin(ang) * real(k, real32)
                self%polar(2, k, irot) = -cos(ang) * real(k, real32)
            end do
        end do
        self%existence = .true.
    end subroutine new

    module subroutine kill( self )
        class(polarft_calc), intent(inout) :: self
        integer :: ieo
        ! every workspace is killed before the deallocation: the release of its handles does not rest on the
        ! finalization of a polymorphic component
        if( allocated(self%ws) )then
            do ieo = 1, size(self%ws)
                call self%ws(ieo)%kill()
            end do
            deallocate(self%ws)
        endif
        if( allocated(self%pinds) ) deallocate(self%pinds)
        if( allocated(self%sigma2_wk) ) deallocate(self%sigma2_wk)
        if( allocated(self%sigma2_wk8) ) deallocate(self%sigma2_wk8)
        if( allocated(self%polar) ) deallocate(self%polar)
        if( allocated(self%sm_islots) ) deallocate(self%sm_islots)
        if( allocated(self%sm_cands) ) deallocate(self%sm_cands)
        if( allocated(self%sm_logz) ) deallocate(self%sm_logz)
        if( allocated(self%sm_maps) ) deallocate(self%sm_maps)
        if( allocated(self%sm_shifts) ) deallocate(self%sm_shifts)
        if( allocated(self%pfts_refs) ) deallocate(self%pfts_refs)
        if( allocated(self%dft_e) ) deallocate(self%dft_e)
        if( allocated(self%ft_ref_terms) ) deallocate(self%ft_ref_terms)
        if( allocated(self%u_next) ) deallocate(self%u_next)
        if( allocated(self%banks_next) ) deallocate(self%banks_next)
        if( allocated(self%l_bank_next) ) deallocate(self%l_bank_next)
        if( allocated(self%refs_next) ) deallocate(self%refs_next)
        if( allocated(self%pair_ptr_next) ) deallocate(self%pair_ptr_next)
        if( allocated(self%rows) ) deallocate(self%rows)
        if( allocated(self%ref_full) ) deallocate(self%ref_full)
        call kill_block_work(self)
        call kill_ptcls(self)
        self%nptcls        = 1
        self%nrefs         = 1
        self%nrots         = 0
        self%pftsz         = 0
        self%pfromto       = 0
        self%kfromto       = 0
        self%nk            = 0
        self%ref_gen       = 0_int64
        self%ref_gen_tiles = -1_int64
        self%ptcl_gen      = 0_int64
        self%ptcl_gen_memo = -1_int64
        self%l_weights     = .false.
        self%ldim          = 0
        self%nspace        = 0
        self%nstates       = 1
        self%wk_gen        = 0_int64
        self%map_ref_gen   = -1_int64
        self%map_wk_gen    = -1_int64
        self%map_kstop     = 0
        self%sm_imap       = 0
        self%sm_ieo        = 0
        self%sm_ptcl_tile  = 16
        self%sm_l_maps     = .false.
        self%sm_l_evidence = .false.
        self%sm_l_profile  = .false.
        self%nref_staged   = 0
        self%l_refs_pending = .false.
        self%l_refs_memoized = .false.
        self%bt            = POLAR_CANON_BT
        self%rt            = POLAR_CANON_RT
        self%tail          = POLARFT_TAILS%graph
        self%route         = POLARFT_REF_ROUTES%host
        self%l_rows        = .false.
        self%l_profile     = .false.
        self%slot_ieo      = 0
        self%msg           = ''
        self%l_mlx         = .false.
        self%nthr          = 1
        self%rnd_seed      = 0
        self%l_keys        = .false.
        self%existence     = .false.
    end subroutine kill

    module subroutine polarft_calc_final( self )
        type(polarft_calc), intent(inout) :: self
        call self%kill
    end subroutine polarft_calc_final

    module subroutine alloc_ptcls( self )
        class(polarft_calc), intent(inout) :: self
        associate( k1 => self%kfromto(1), k2 => self%kfromto(2), n => self%nptcls )
            allocate(self%iseven(n), self%wsqsums_ptcls(n), self%kshell_sqsums_ptcls(k1:k2, n), &
                &self%ft_ptcl_ctf(self%pftsz+1, k1:k2, n), self%ft_ctf2(self%pftsz+1, k1:k2, n), &
                &self%ft_ptcl_wterms(2 * self%nk, self%pftsz+1, n))
        end associate
        allocate(self%l_ptcl_set(self%nptcls))
        self%l_ptcl_set          = .false.
        self%nptcl_staged        = 0
        self%iseven              = .true.
        self%wsqsums_ptcls       = 0._real64
        self%kshell_sqsums_ptcls = 0._real64
        self%ft_ptcl_ctf         = cmplx(0._real32, 0._real32, real32)
        self%ft_ctf2             = cmplx(0._real32, 0._real32, real32)
        self%ft_ptcl_wterms      = cmplx(0._real32, 0._real32, real32)
    end subroutine alloc_ptcls

    module subroutine kill_ptcls( self )
        class(polarft_calc), intent(inout) :: self
        if( allocated(self%iseven) ) deallocate(self%iseven)
        if( allocated(self%wsqsums_ptcls) ) deallocate(self%wsqsums_ptcls)
        if( allocated(self%kshell_sqsums_ptcls) ) deallocate(self%kshell_sqsums_ptcls)
        if( allocated(self%ft_ptcl_ctf) ) deallocate(self%ft_ptcl_ctf)
        if( allocated(self%ft_ctf2) ) deallocate(self%ft_ctf2)
        if( allocated(self%ft_ptcl_wterms) ) deallocate(self%ft_ptcl_wterms)
        if( allocated(self%pfts_ptcls) ) deallocate(self%pfts_ptcls)
        if( allocated(self%ctfmats) ) deallocate(self%ctfmats)
        if( allocated(self%l_ptcl_set) ) deallocate(self%l_ptcl_set)
    end subroutine kill_ptcls

    module subroutine set_eo( self, iptcl, is_even )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: iptcl
        logical,             intent(in)    :: is_even
        integer :: i
        i = ptcl_slot(self, iptcl)
        if( i == 0 )then
            self%msg = 'polarft_calc%set_eo: refused: the particle is not in the batch'
            return
        endif
        self%msg       = ''
        self%iseven(i) = is_even
        self%ptcl_gen  = self%ptcl_gen + 1_int64
    end subroutine set_eo

    module subroutine set_sigma2_weights( self, sigma2_wk8 )
        class(polarft_calc), intent(inout) :: self
        real(real64),        intent(in)    :: sigma2_wk8(:,:)
        if( .not. self%existence )then
            self%msg = 'polarft_calc%set_sigma2_weights: refused: no calculator (new)'
            return
        endif
        if( any(shape(sigma2_wk8) /= [self%nk, 2]) )then
            self%msg = 'polarft_calc%set_sigma2_weights: refused: the weights are not (shells, 2)'
            return
        endif
        self%msg       = ''
        self%sigma2_wk8 = sigma2_wk8
        self%sigma2_wk  = real(sigma2_wk8, real32)
        self%wk_gen     = self%wk_gen + 1_int64
        self%l_weights = .true.
        self%ptcl_gen  = self%ptcl_gen + 1_int64
    end subroutine set_sigma2_weights

    module subroutine set_tile_plan( self, bt, rt )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: bt, rt
        if( bt < 1 .or. rt < 1 )then
            self%msg = 'polarft_calc%set_tile_plan: refused: the tile plan needs bt and rt of at least 1'
            return
        endif
        self%msg = ''
        if( bt /= self%bt .or. rt /= self%rt ) self%ref_gen_tiles = -1_int64
        self%bt = bt
        self%rt = rt
    end subroutine set_tile_plan

    module subroutine set_tail_form( self, form )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: form
        if( form /= POLARFT_TAILS%graph .and. form /= POLARFT_TAILS%metal )then
            self%msg = 'polarft_calc%set_tail_form: refused: the form is one of POLARFT_TAILS'
            return
        endif
        self%msg = ''
        if( form /= self%tail ) self%ref_gen_tiles = -1_int64
        self%tail = form
    end subroutine set_tail_form

    module subroutine set_ref_route( self, route )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: route
        if( .not. self%existence )then
            self%msg = 'polarft_calc%set_ref_route: refused: no calculator (new)'
        else if( route /= POLARFT_REF_ROUTES%host .and. route /= POLARFT_REF_ROUTES%device )then
            self%msg = 'polarft_calc%set_ref_route: refused: the route is one of POLARFT_REF_ROUTES'
        else if( route == POLARFT_REF_ROUTES%device .and. .not. self%l_mlx )then
            self%msg = 'polarft_calc%set_ref_route: refused: the device route needs the MLX backend'
        else if( self%l_refs_pending )then
            self%msg = 'polarft_calc%set_ref_route: refused: references wait to be memoized (memoize_refs)'
        else if( self%l_refs_memoized .and. route /= self%route )then
            self%msg = 'polarft_calc%set_ref_route: refused: the references are memoized on the other route (kill and new)'
        else
            self%msg = ''
        endif
        if( len(self%msg) > 0 ) return
        if( route /= self%route ) self%ref_gen_tiles = -1_int64
        self%route = route
    end subroutine set_ref_route

    pure module function message( self ) result(msg)
        class(polarft_calc), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

    pure module integer function get_nrefs( self )
        class(polarft_calc), intent(in) :: self
        get_nrefs = self%nrefs
    end function get_nrefs

    pure module integer function get_pftsz( self )
        class(polarft_calc), intent(in) :: self
        get_pftsz = self%pftsz
    end function get_pftsz

    pure module function get_tile_plan( self ) result(plan)
        class(polarft_calc), intent(in) :: self
        integer :: plan(2)
        plan = [self%bt, self%rt]
    end function get_tile_plan

    pure module function get_kfromto( self ) result(kfromto)
        class(polarft_calc), intent(in) :: self
        integer :: kfromto(2)
        kfromto = self%kfromto
    end function get_kfromto

    module subroutine get_polar_coords( self, dim, coords )
        class(polarft_calc), intent(inout) :: self
        integer,             intent(in)    :: dim
        real(real32),        intent(out)   :: coords(self%kfromto(1):self%kfromto(2), self%pftsz)
        coords = 0._real32
        if( .not. self%existence )then
            self%msg = 'polarft_calc%get_polar_coords: refused: no calculator (new)'
            return
        endif
        if( dim /= 1 .and. dim /= 2 )then
            self%msg = 'polarft_calc%get_polar_coords: refused: invalid coordinate dimension'
            return
        endif
        self%msg = ''
        coords   = self%polar(dim, self%kfromto(1):self%kfromto(2), 1:self%pftsz)
    end subroutine get_polar_coords

    module subroutine vol_pad2ref_pfts_opt( self, vol_pad, eulspace, state, iseven )
        class(polarft_calc), intent(inout) :: self
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        integer,             intent(in)    :: state
        logical,             intent(in)    :: iseven
        complex(real32), allocatable :: refs_state(:,:,:)
        integer                      :: iref_from, iref_to, i
        if( .not. self%existence )then
            self%msg = 'vol_pad2ref_pfts_opt: refused: no calculator (new)'
            return
        endif
        if( state < 1 .or. state > self%nstates )then
            self%msg = 'vol_pad2ref_pfts_opt: refused: state out of range'
            return
        endif
        if( self%nspace < 1 )then
            self%msg = 'vol_pad2ref_pfts_opt: refused: nspace must be at least 1'
            return
        endif
        iref_from = (state - 1) * self%nspace + 1
        iref_to   = iref_from + self%nspace - 1
        if( iref_to > self%nrefs )then
            self%msg = 'vol_pad2ref_pfts_opt: refused: reference range exceeds allocated bank'
            return
        endif
        self%msg = ''
        if( self%l_mlx .and. self%route == POLARFT_REF_ROUTES%device )then
            call vol_pad2ref_pfts_opt_mlx(self, vol_pad, eulspace, state, iseven)
            return
        endif
        allocate(refs_state(self%pftsz, self%nk, self%nspace))
        call fproject_polar_batch_opt(vol_pad, eulspace, self%nspace, self, refs_state)
        if( len(vol_pad%message()) > 0 )then
            self%msg = vol_pad%message()
            return
        endif
        do i = 1, self%nspace
            call self%set_ref_pft(iref_from + i - 1, cmplx(refs_state(:, :, i), kind=real64), iseven)
        end do
    end subroutine vol_pad2ref_pfts_opt

    pure module logical function ptcl_iseven( self, iptcl )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: iptcl
        integer :: i
        ptcl_iseven = .false.
        i           = ptcl_slot(self, iptcl)
        if( i > 0 ) ptcl_iseven = self%iseven(i)
    end function ptcl_iseven

    ! the batch slot of particle iptcl (project index), 0 when the calculator does not hold it
    pure module integer function ptcl_slot( self, iptcl )
        class(polarft_calc), intent(in) :: self
        integer,             intent(in) :: iptcl
        ptcl_slot = 0
        if( .not. self%existence ) return
        if( iptcl < self%pfromto(1) .or. iptcl > self%pfromto(2) ) return
        ptcl_slot = self%pinds(iptcl)
    end function ptcl_slot

end submodule mlxf_toy_polarft_core
