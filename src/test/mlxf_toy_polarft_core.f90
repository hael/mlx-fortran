!@descr: the toy polar calculator's core: new, kill, the particles' halves, the shell weights, the tile plan, the message
submodule (mlxf_toy_polarft_calc) mlxf_toy_polarft_core
implicit none

contains

    module subroutine new( self, params, nrefs, pfromto, kfromto )
        class(polarft_calc), intent(inout) :: self
        type(parameters),    intent(in)    :: params
        integer,             intent(in)    :: nrefs
        integer,             intent(in)    :: pfromto(2), kfromto(2)
        integer :: i
        call self%kill
        if( params%pftsz < 2 .or. mod(params%pftsz, 2) /= 0 )then
            self%msg = 'polarft_calc%new: refused: pftsz must be even and at least 2'
        else if( nrefs < 1 )then
            self%msg = 'polarft_calc%new: refused: nrefs must be at least 1'
        else if( pfromto(1) < 1 .or. pfromto(2) < pfromto(1) )then
            self%msg = 'polarft_calc%new: refused: pfromto must be an ascending range of positive indices'
        else if( kfromto(1) < 1 .or. kfromto(2) < kfromto(1) )then
            self%msg = 'polarft_calc%new: refused: kfromto must be an ascending range of positive shells'
        endif
        if( len(self%msg) > 0 ) return
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
        allocate(self%ft_ref(self%pftsz+1, kfromto(1):kfromto(2), nrefs, N_REF_PARITIES), &
            &self%ft_ref2(self%pftsz+1, kfromto(1):kfromto(2), nrefs, N_REF_PARITIES), &
            &self%sigma2_wk(kfromto(1):kfromto(2), 2), self%sigma2_wk8(kfromto(1):kfromto(2), 2), &
            &self%ws(N_REF_PARITIES))
        self%ft_ref    = cmplx(0._real32, 0._real32, real32)
        self%ft_ref2   = cmplx(0._real32, 0._real32, real32)
        self%sigma2_wk  = 0._real32
        self%sigma2_wk8 = 0._real64
        self%ldim       = [params%box, params%box, 1]
        self%existence = .true.
    end subroutine new

    module subroutine kill( self )
        class(polarft_calc), intent(inout) :: self
        integer :: ieo
        if( allocated(self%ws) )then
            do ieo = 1, size(self%ws)
                call self%ws(ieo)%kill()
            end do
            deallocate(self%ws)
        endif
        if( allocated(self%pinds) ) deallocate(self%pinds)
        if( allocated(self%sigma2_wk) ) deallocate(self%sigma2_wk)
        if( allocated(self%sigma2_wk8) ) deallocate(self%sigma2_wk8)
        if( allocated(self%sm_islots) ) deallocate(self%sm_islots)
        if( allocated(self%sm_cands) ) deallocate(self%sm_cands)
        if( allocated(self%sm_logz) ) deallocate(self%sm_logz)
        if( allocated(self%sm_maps) ) deallocate(self%sm_maps)
        if( allocated(self%pfts_refs) ) deallocate(self%pfts_refs)
        if( allocated(self%dft_e) ) deallocate(self%dft_e)
        if( allocated(self%ft_ref) ) deallocate(self%ft_ref)
        if( allocated(self%ft_ref2) ) deallocate(self%ft_ref2)
        if( allocated(self%u_next) ) deallocate(self%u_next)
        if( allocated(self%banks_next) ) deallocate(self%banks_next)
        if( allocated(self%l_bank_next) ) deallocate(self%l_bank_next)
        if( allocated(self%rows) ) deallocate(self%rows)
        call kill_ptcls(self)
        self%nptcls        = 1
        self%nrefs         = 1
        self%nrots         = 0
        self%pftsz         = 0
        self%pfromto       = 0
        self%kfromto       = 0
        self%nk            = 0
        self%ref_gen       = 0_int64
        self%ref_gen_bins  = -1_int64
        self%ptcl_gen      = 0_int64
        self%ptcl_gen_memo = -1_int64
        self%l_weights     = .false.
        self%ldim          = 0
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
        self%bt            = POLAR_CANON_BT
        self%rt            = POLAR_CANON_RT
        self%l_rows        = .false.
        self%l_profile     = .false.
        self%slot_ieo      = 0
        self%msg           = ''
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
                &self%ft_ptcl_ctf(self%pftsz+1, k1:k2, n), self%ft_ctf2(self%pftsz+1, k1:k2, n))
        end associate
        allocate(self%l_ptcl_set(self%nptcls))
        self%l_ptcl_set          = .false.
        self%nptcl_staged        = 0
        self%iseven              = .true.
        self%wsqsums_ptcls       = 0._real64
        self%kshell_sqsums_ptcls = 0._real64
        self%ft_ptcl_ctf         = cmplx(0._real32, 0._real32, real32)
        self%ft_ctf2             = cmplx(0._real32, 0._real32, real32)
    end subroutine alloc_ptcls

    module subroutine kill_ptcls( self )
        class(polarft_calc), intent(inout) :: self
        if( allocated(self%iseven) ) deallocate(self%iseven)
        if( allocated(self%wsqsums_ptcls) ) deallocate(self%wsqsums_ptcls)
        if( allocated(self%kshell_sqsums_ptcls) ) deallocate(self%kshell_sqsums_ptcls)
        if( allocated(self%ft_ptcl_ctf) ) deallocate(self%ft_ptcl_ctf)
        if( allocated(self%ft_ctf2) ) deallocate(self%ft_ctf2)
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
        if( bt /= self%bt .or. rt /= self%rt ) self%ref_gen_bins = -1_int64
        self%bt = bt
        self%rt = rt
    end subroutine set_tile_plan

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
