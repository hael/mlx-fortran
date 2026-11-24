!@descr: the polar table workspace's lifecycle: references validated and prepared as resident tiles, invalidation, teardown
submodule (mlxf_kernel_polar_table) mlxf_kernel_polar_table_lifecycle
use mlxf, only: mlx_from, mlx_eval, mlx_compile
implicit none

contains

    module subroutine polar_table_new( self, refs, status )
        class(polar_table),     intent(inout) :: self
        type(polar_table_refs), intent(in)    :: refs
        integer,                intent(out)   :: status
        complex(real32), allocatable :: tiles(:,:,:,:), g(:,:)
        real(real32),    allocatable :: rtiles(:,:,:,:)
        type(mlx_function)           :: f
        integer                      :: n1, nk2, nrefs, ntiles, t, c, r, k, p, ierr
        call self%kill()
        status = 1
        call check_refs(refs, self%msg)
        if( len(self%msg) > 0 ) return
        n1     = refs%pftsz + 1
        nk2    = 2 * refs%nk
        nrefs  = size(refs%ids)
        ntiles = (nrefs + refs%rt - 1) / refs%rt
        ! one tile per rt references, the last one padded with zero columns
        allocate(tiles(nk2, refs%rt, n1, ntiles), g(nk2, refs%rt), stat=ierr)
        if( ierr /= 0 )then
            self%msg = 'polar_table%new: the host staging of the reference tiles could not be allocated'
            return
        endif
        tiles = cmplx(0._real32, 0._real32, real32)
        do t = 1, ntiles
            do c = 1, refs%rt
                r = (t - 1) * refs%rt + c
                if( r > nrefs ) exit
                do k = 1, refs%nk
                    tiles(k, c, :, t)           = refs%ft_ref2(:, k, r)
                    tiles(refs%nk + k, c, :, t) = conjg(refs%ft_ref(:, k, r))
                end do
            end do
        end do
        ! the tile G as the real block [[Re G, Im G], [-Im G, Re G]] of every bin
        allocate(rtiles(2*nk2, 2*refs%rt, n1, ntiles), stat=ierr)
        if( ierr /= 0 )then
            self%msg = 'polar_table%new: the host staging of the packed reference tiles could not be allocated'
            return
        endif
        do t = 1, ntiles
            do p = 1, n1
                g = tiles(:, :, p, t)
                rtiles(1:nk2, 1:refs%rt, p, t)                 = real(g)
                rtiles(1:nk2, refs%rt+1:2*refs%rt, p, t)       = aimag(g)
                rtiles(nk2+1:2*nk2, 1:refs%rt, p, t)           = -aimag(g)
                rtiles(nk2+1:2*nk2, refs%rt+1:2*refs%rt, p, t) = real(g)
            end do
        end do
        deallocate(tiles)
        self%refs = mlx_from(rtiles)
        deallocate(rtiles)
        ! the distances and draw as one compiled function, traced at the first tile on the current device
        f         = mlx_function(polar_tail_callback)
        self%tail = mlx_compile(f, shapeless=.false.)
        call mlx_eval(self%refs, status=ierr)
        if( ierr /= 0 )then
            self%msg = 'polar_table%new: the reference tiles could not be evaluated'
            call self%kill()
            return
        endif
        self%pftsz      = refs%pftsz
        self%nk         = refs%nk
        self%nrots      = 2 * refs%pftsz
        self%half       = refs%half
        self%rt         = refs%rt
        self%bt         = refs%bt
        self%nrefs      = nrefs
        self%ntiles     = ntiles
        self%generation = refs%generation
        self%ids        = refs%ids
        self%prepared   = .true.
        status          = 0
    end subroutine polar_table_new

    ! the reason refs cannot be prepared, or an empty string
    subroutine check_refs( refs, msg )
        type(polar_table_refs),        intent(in)  :: refs
        character(len=:), allocatable, intent(out) :: msg
        integer :: n1, i
        msg = ''
        if( refs%pftsz < 2 .or. mod(refs%pftsz, 2) /= 0 )then
            msg = 'polar_table%new: pftsz must be even and at least 2'
        else if( refs%nk < 1 )then
            msg = 'polar_table%new: nk must be at least 1'
        else if( refs%half /= 1 .and. refs%half /= 2 )then
            msg = 'polar_table%new: half must be 1 or 2'
        else if( refs%rt < 1 .or. refs%bt < 1 )then
            msg = 'polar_table%new: the tile plan needs rt and bt of at least 1'
        else if( .not. allocated(refs%ids) )then
            msg = 'polar_table%new: no reference IDs'
        endif
        if( len(msg) > 0 ) return
        if( size(refs%ids) < 1 )then
            msg = 'polar_table%new: no reference IDs'
            return
        endif
        if( any(refs%ids < 1) )then
            msg = 'polar_table%new: reference IDs are global and positive'
            return
        endif
        do i = 2, size(refs%ids)
            if( any(refs%ids(1:i-1) == refs%ids(i)) )then
                msg = 'polar_table%new: a reference ID is listed twice'
                return
            endif
        end do
        if( .not. allocated(refs%ft_ref) .or. .not. allocated(refs%ft_ref2) )then
            msg = 'polar_table%new: the reference memos are missing'
            return
        endif
        n1 = refs%pftsz + 1
        if( any(shape(refs%ft_ref) /= [n1, refs%nk, size(refs%ids)]) .or. &
            &any(shape(refs%ft_ref2) /= [n1, refs%nk, size(refs%ids)]) )then
            msg = 'polar_table%new: the reference memos are not (pftsz+1, nk, references)'
        endif
    end subroutine check_refs

    module subroutine polar_table_invalidate( self )
        class(polar_table), intent(inout) :: self
        call self%refs%kill()
        call polar_table_drop_maps(self)
        self%prepared = .false.
    end subroutine polar_table_invalidate

    module subroutine polar_table_drop_maps( self )
        class(polar_table), intent(inout) :: self
        call self%rfull%kill()
        call self%ref2b%kill()
        call self%wfold%kill()
        call self%ffold%kill()
        call self%wband%kill()
        call self%cellx%kill()
        call self%celly%kill()
        call self%cellr2%kill()
        call self%cellprior%kill()
        call self%map_select%kill()
        call self%map_reduce%kill()
        call self%map_evidence%kill()
        if( allocated(self%map_rho) ) deallocate(self%map_rho)
        if( allocated(self%map_nharm) ) deallocate(self%map_nharm)
        self%maps_ready    = .false.
        self%map_nkb       = 0
        self%map_nrho      = 0
        self%map_nalpha    = 0
        self%map_norder    = 0
        self%map_lse_prior = 0._real64
    end subroutine polar_table_drop_maps

    module subroutine polar_table_kill( self )
        class(polar_table), intent(inout) :: self
        integer :: i
        call self%refs%kill()
        call self%tail%kill()
        call polar_table_drop_maps(self)
        do i = 1, POLAR_TABLE_NSLOTS
            call self%slots(i)%dists%kill()
            call self%slots(i)%irots%kill()
            call self%slots(i)%rows%kill()
            self%slots(i)%busy = .false.
        end do
        if( allocated(self%ids) ) deallocate(self%ids)
        self%prepared   = .false.
        self%pftsz      = 0
        self%nk         = 0
        self%nrots      = 0
        self%half       = 0
        self%rt         = 0
        self%bt         = 0
        self%nrefs      = 0
        self%ntiles     = 0
        self%generation = -1_int64
    end subroutine polar_table_kill

    module subroutine polar_table_final( self )
        type(polar_table), intent(inout) :: self
        call self%kill()
    end subroutine polar_table_final

    pure module logical function prepared_now( self )
        class(polar_table), intent(in) :: self
        prepared_now = self%prepared
    end function prepared_now

    pure module function stage_seconds( self ) result(t)
        class(polar_table), intent(in) :: self
        real(real64) :: t(5)
        t = self%stage_s
    end function stage_seconds

    pure module function message( self ) result(msg)
        class(polar_table), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

end submodule mlxf_kernel_polar_table_lifecycle
