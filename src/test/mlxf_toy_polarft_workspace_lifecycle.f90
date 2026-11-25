!@descr: the polar workspace's lifecycle: reference memos validated and prepared as resident tiles with their tail, teardown
submodule (mlxf_toy_polarft_workspace) mlxf_toy_polarft_workspace_lifecycle
use mlxf, only: mlx_from, mlx_to, mlx_eval, mlx_compile, mlx_zeros, mlx_slice, mlx_slice_update, mlx_concatenate, &
                mlx_fft, mlx_rfft, mlx_permute, reshape, conjg, real, aimag, MLX_DTYPES
implicit none

contains

    module subroutine polarft_workspace_new( self, spec, ft_ref, ft_ref2, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_tile_spec),  intent(in)    :: spec
        complex(real32),          intent(in)    :: ft_ref(:,:,:), ft_ref2(:,:,:)
        integer,                  intent(out)   :: status
        complex(real32), allocatable :: tiles(:,:,:,:), g(:,:)
        real(real32),    allocatable :: rtiles(:,:,:,:)
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
        call finish_tiles(self, spec, nrefs, status)
    end subroutine polarft_workspace_new

    ! the tail of spec's form beside the tiles in self%refs, the tiles evaluated and the preparation recorded; a
    ! failure drops the tiles (status /= 0, message)
    subroutine finish_tiles( self, spec, nrefs, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_tile_spec),  intent(in)    :: spec
        integer,                  intent(in)    :: nrefs
        integer,                  intent(out)   :: status
        type(mlx_function) :: f
        integer            :: ierr
        status = 1
        if( spec%tail == POLARFT_TAILS%metal )then
            call polarft_workspace_new_tail(self, spec, ierr)
            if( ierr /= 0 )then
                call drop_tiles(self)
                return
            endif
        else
            ! the distances and draw as one compiled function, traced at the first tile on the current device
            f         = mlx_function(polar_tail_callback)
            self%tail = mlx_compile(f, shapeless=.false.)
        endif
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
        self%ntiles   = (nrefs + spec%rt - 1) / spec%rt
        self%prepared = .true.
        status        = 0
    end subroutine finish_tiles

    module subroutine set_sections( self, bank, iref_from, nrefs, status )
        class(polarft_workspace), intent(inout) :: self
        type(mlx_array),          intent(in)    :: bank
        integer,                  intent(in)    :: iref_from, nrefs
        integer,                  intent(out)   :: status
        integer, allocatable :: bs(:)
        status   = 1
        self%msg = ''
        bs       = bank%shape()
        if( size(bs) /= 2 )then
            self%msg = 'polarft_workspace%set_sections: refused: the bank is not (pftsz nk, nspace)'
            return
        endif
        if( iref_from < 1 .or. iref_from + bs(2) - 1 > nrefs )then
            self%msg = 'polarft_workspace%set_sections: refused: the bank does not fit the references'
            return
        endif
        if( self%l_sections .and. (self%sec_npts /= bs(1) .or. self%sec_nrefs /= nrefs) )then
            self%msg = 'polarft_workspace%set_sections: refused: the bank does not match the sections held'
            return
        endif
        call self%memo_ref%kill()
        call self%memo_ref2%kill()
        self%l_memos = .false.
        if( iref_from == 1 .and. bs(2) == nrefs )then
            ! a bank of every reference replaces the sections
            self%sections = bank
        else if( .not. self%l_sections )then
            self%sections = mlx_slice_update(mlx_zeros([bs(1), nrefs], dtype=MLX_DTYPES%complex64), bank, &
                &[1, iref_from], [bs(1), iref_from + bs(2) - 1])
        else
            self%sections = mlx_slice_update(self%sections, bank, [1, iref_from], [bs(1), iref_from + bs(2) - 1])
        endif
        self%sec_npts   = bs(1)
        self%sec_nrefs  = nrefs
        self%l_sections = .true.
        status = 0
    end subroutine set_sections

    module subroutine memoize_sections( self, pftsz, nk, status )
        class(polarft_workspace), intent(inout) :: self
        integer,                  intent(in)    :: pftsz, nk
        integer,                  intent(out)   :: status
        type(mlx_array) :: z, ring(2), full, a2
        status   = 1
        self%msg = ''
        if( .not. self%l_sections )then
            self%msg = 'polarft_workspace%memoize_sections: refused: no projected sections'
            return
        endif
        if( pftsz * nk /= self%sec_npts )then
            self%msg = 'polarft_workspace%memoize_sections: refused: the sections are not pftsz nk points'
            return
        endif
        z       = reshape(self%sections, [pftsz, nk, self%sec_nrefs])
        ring(1) = z
        ring(2) = conjg(z)
        full    = mlx_concatenate(ring, dim=1)
        self%memo_ref = mlx_slice(mlx_fft(full, dim=1), [1, 1, 1], [pftsz + 1, nk, self%sec_nrefs])
        a2      = real(z) * real(z) + aimag(z) * aimag(z)
        ring(1) = a2
        ring(2) = a2
        full    = mlx_concatenate(ring, dim=1)
        self%memo_ref2 = conjg(mlx_rfft(full, dim=1))
        call mlx_eval(self%memo_ref, status=status)
        if( status == 0 ) call mlx_eval(self%memo_ref2, status=status)
        if( status /= 0 )then
            self%msg = 'polarft_workspace%memoize_sections: the memos could not be evaluated'
            call self%memo_ref%kill()
            call self%memo_ref2%kill()
            return
        endif
        call self%sections%kill()
        self%l_sections = .false.
        self%l_memos    = .true.
    end subroutine memoize_sections

    module subroutine new_from_memos( self, spec, status )
        class(polarft_workspace), intent(inout) :: self
        type(polarft_tile_spec),  intent(in)    :: spec
        integer,                  intent(out)   :: status
        type(mlx_array) :: g(2), a, re, im, top(2), bottom(2), half(2)
        integer         :: n1, nk2, nrefs, ntiles, npad
        call drop_tiles(self)
        status = 1
        if( .not. self%l_memos )then
            self%msg = 'polarft_workspace%new_from_memos: refused: no device memos (memoize_refs on the device route)'
            return
        endif
        if( spec%pftsz < 2 .or. mod(spec%pftsz, 2) /= 0 .or. spec%nk < 1 .or. spec%rt < 1 .or. spec%bt < 1 )then
            self%msg = 'polarft_workspace%new_from_memos: refused: invalid tile plan'
            return
        endif
        n1     = spec%pftsz + 1
        nk2    = 2 * spec%nk
        nrefs  = self%sec_nrefs
        ntiles = (nrefs + spec%rt - 1) / spec%rt
        npad   = ntiles * spec%rt - nrefs
        ! G per bin: rows 1..nk ft_ref2, rows nk+1..2nk conj(ft_ref), a column per reference, zero columns last
        g(1) = self%memo_ref2
        g(2) = conjg(self%memo_ref)
        a    = mlx_concatenate(g, dim=2)
        if( npad > 0 )then
            g(1) = a
            g(2) = mlx_zeros([n1, nk2, npad], dtype=MLX_DTYPES%complex64)
            a    = mlx_concatenate(g, dim=3)
        endif
        a  = mlx_permute(reshape(a, [n1, nk2, spec%rt, ntiles]), [2, 3, 1, 4])
        ! the tile G of every bin as the real block [[Re G, Im G], [-Im G, Re G]]
        re = real(a)
        im = aimag(a)
        top(1)    = re
        top(2)    = im
        bottom(1) = -im
        bottom(2) = re
        half(1)   = mlx_concatenate(top, dim=2)
        half(2)   = mlx_concatenate(bottom, dim=2)
        self%refs = mlx_concatenate(half, dim=1)
        call finish_tiles(self, spec, nrefs, status)
        if( status /= 0 ) return
        call self%memo_ref%kill()
        call self%memo_ref2%kill()
        self%l_memos = .false.
    end subroutine new_from_memos

    module subroutine get_section( self, iref, pft, status )
        class(polarft_workspace), intent(inout) :: self
        integer,                  intent(in)    :: iref
        complex(real32),          intent(out)   :: pft(:,:)
        integer,                  intent(out)   :: status
        status   = 1
        self%msg = ''
        pft      = cmplx(0._real32, 0._real32, real32)
        if( .not. self%l_sections )then
            self%msg = 'polarft_workspace%get_section: refused: no projected sections'
            return
        endif
        if( iref < 1 .or. iref > self%sec_nrefs .or. size(pft) /= self%sec_npts )then
            self%msg = 'polarft_workspace%get_section: refused: no such section, or the wrong shape'
            return
        endif
        call mlx_to(pft, reshape(mlx_slice(self%sections, [1, iref], [self%sec_npts, iref]), shape(pft)), status=status)
        if( status /= 0 ) self%msg = 'polarft_workspace%get_section: the section could not be copied'
    end subroutine get_section

    pure module logical function has_sections( self )
        class(polarft_workspace), intent(in) :: self
        has_sections = self%l_sections
    end function has_sections

    pure module logical function has_memos( self )
        class(polarft_workspace), intent(in) :: self
        has_memos = self%l_memos
    end function has_memos

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
        call self%sections%kill()
        call self%memo_ref%kill()
        call self%memo_ref2%kill()
        self%l_sections = .false.
        self%l_memos    = .false.
        self%sec_npts   = 0
        self%sec_nrefs  = 0
    end subroutine polarft_workspace_kill

    ! the reference tiles, the blocks in flight and the record of their preparation; the shift maps stay
    subroutine drop_tiles( self )
        class(polarft_workspace), intent(inout) :: self
        integer :: i
        call self%refs%kill()
        call self%tail%kill()
        call self%tail_kernel%kill()
        call self%tail_kernel_rows%kill()
        call self%tail_par%kill()
        self%l_tail_rows = .false.
        self%tail_form   = POLARFT_TAILS%graph
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
