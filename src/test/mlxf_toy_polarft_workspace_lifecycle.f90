!@descr: the polar workspace's lifecycle: reference memos validated and prepared as resident tiles, teardown
submodule (mlxf_toy_polarft_workspace) mlxf_toy_polarft_workspace_lifecycle
use mlxf, only: mlx_from, mlx_eval, mlx_compile
implicit none

contains

    module subroutine polarft_workspace_new( self, spec, ft_ref, ft_ref2, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_tile_spec),  intent(in)    :: spec
        complex(real32),          intent(in)    :: ft_ref(:,:,:), ft_ref2(:,:,:)
        integer,                  intent(out)   :: status
        complex(real32), allocatable :: tiles(:,:,:,:), g(:,:)
        real(real32),    allocatable :: rtiles(:,:,:,:)
        type(mlx_function)           :: f
        integer                      :: n1, nk2, nrefs, ntiles, t, c, r, k, p, ierr
        call drop_tiles(self)
        status = 1
        call check_refs(spec, ft_ref, ft_ref2, self%msg)
        if( len(self%msg) > 0 ) return
        n1     = spec%pftsz + 1
        nk2    = 2 * spec%nk
        nrefs  = size(ft_ref, 3)
        ntiles = (nrefs + spec%rt - 1) / spec%rt
        ! one tile per rt references, the last one padded with zero columns
        allocate(tiles(nk2, spec%rt, n1, ntiles), g(nk2, spec%rt), stat=ierr)
        if( ierr /= 0 )then
            self%msg = 'polarft_workspace%new: the host staging of the reference tiles could not be allocated'
            return
        endif
        tiles = cmplx(0._real32, 0._real32, real32)
        do t = 1, ntiles
            do c = 1, spec%rt
                r = (t - 1) * spec%rt + c
                if( r > nrefs ) exit
                do k = 1, spec%nk
                    tiles(k, c, :, t)           = ft_ref2(:, k, r)
                    tiles(spec%nk + k, c, :, t) = conjg(ft_ref(:, k, r))
                end do
            end do
        end do
        ! the tile G as the real block [[Re G, Im G], [-Im G, Re G]] of every bin
        allocate(rtiles(2*nk2, 2*spec%rt, n1, ntiles), stat=ierr)
        if( ierr /= 0 )then
            self%msg = 'polarft_workspace%new: the host staging of the packed reference tiles could not be allocated'
            return
        endif
        do t = 1, ntiles
            do p = 1, n1
                g = tiles(:, :, p, t)
                rtiles(1:nk2, 1:spec%rt, p, t)                 = real(g)
                rtiles(1:nk2, spec%rt+1:2*spec%rt, p, t)       = aimag(g)
                rtiles(nk2+1:2*nk2, 1:spec%rt, p, t)           = -aimag(g)
                rtiles(nk2+1:2*nk2, spec%rt+1:2*spec%rt, p, t) = real(g)
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
            self%msg = 'polarft_workspace%new: the reference tiles could not be evaluated'
            call drop_tiles(self)
            return
        endif
        self%pftsz    = spec%pftsz
        self%nk       = spec%nk
        self%nrots    = 2 * spec%pftsz
        self%rt       = spec%rt
        self%bt       = spec%bt
        self%nrefs    = nrefs
        self%ntiles   = ntiles
        self%prepared = .true.
        status        = 0
    end subroutine polarft_workspace_new

    ! the reason the memos cannot be prepared under spec, or an empty string
    subroutine check_refs( spec, ft_ref, ft_ref2, msg )
        type(polarft_tile_spec),       intent(in)  :: spec
        complex(real32),               intent(in)  :: ft_ref(:,:,:), ft_ref2(:,:,:)
        character(len=:), allocatable, intent(out) :: msg
        integer :: n1
        msg = ''
        if( spec%pftsz < 2 .or. mod(spec%pftsz, 2) /= 0 )then
            msg = 'polarft_workspace%new: pftsz must be even and at least 2'
        else if( spec%nk < 1 )then
            msg = 'polarft_workspace%new: nk must be at least 1'
        else if( spec%rt < 1 .or. spec%bt < 1 )then
            msg = 'polarft_workspace%new: the tile plan needs rt and bt of at least 1'
        else if( size(ft_ref, 3) < 1 )then
            msg = 'polarft_workspace%new: no references'
        endif
        if( len(msg) > 0 ) return
        n1 = spec%pftsz + 1
        if( any(shape(ft_ref) /= [n1, spec%nk, size(ft_ref, 3)]) .or. any(shape(ft_ref2) /= shape(ft_ref)) )then
            msg = 'polarft_workspace%new: the reference memos are not (pftsz+1, nk, references)'
        endif
    end subroutine check_refs

    module subroutine polarft_workspace_kill( self )
        class(polarft_workspace), intent(inout) :: self
        call drop_tiles(self)
        call self%kill_maps()
    end subroutine polarft_workspace_kill

    ! the reference tiles, the blocks in flight and the record of their preparation; the shift maps stay
    subroutine drop_tiles( self )
        class(polarft_workspace), intent(inout) :: self
        integer :: i
        call self%refs%kill()
        call self%tail%kill()
        do i = 1, POLARFT_NSLOTS
            call self%slots(i)%dists%kill()
            call self%slots(i)%irots%kill()
            call self%slots(i)%rows%kill()
            self%slots(i)%busy = .false.
        end do
        if( allocated(self%rows_host) ) deallocate(self%rows_host)
        self%prepared = .false.
        self%pftsz    = 0
        self%nk       = 0
        self%nrots    = 0
        self%rt       = 0
        self%bt       = 0
        self%nrefs    = 0
        self%ntiles   = 0
    end subroutine drop_tiles

    module subroutine polarft_workspace_final( self )
        type(polarft_workspace), intent(inout) :: self
        call self%kill()
    end subroutine polarft_workspace_final

    pure module function stage_seconds( self ) result(t)
        class(polarft_workspace), intent(in) :: self
        real(real64) :: t(5)
        t = self%stage_s
    end function stage_seconds

    pure module function message( self ) result(msg)
        class(polarft_workspace), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

end submodule mlxf_toy_polarft_workspace_lifecycle
