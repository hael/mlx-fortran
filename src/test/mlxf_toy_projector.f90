!@descr: the toy projector (test only): a miniature of SIMPLE's projector with the image procedures the reprojection calls
! The type and its procedures carry SIMPLE's names (projector, with new, set_rmat, pad_fft and kill of the image it
! extends in SIMPLE); scripts/toy_mirror.txt lists each as mirrored or as an addition. The host holds the real
! volume rmat (N, N, N), voxel i at the centred x = i - 1 - N/2. pad_fft writes it into a padded box of side M
! with its origin at voxel 1 (SIMPLE's fused pad and fftshift) and hands it to the padded projector's workspace,
! which transforms it; expand_cmat makes SIMPLE's expanded cube there. All MLX state is the component ws, made with
! the projector and released in kill; fproject_polar_batch_opt reads the cube through it, as SIMPLE's reads the
! public cmat_exp.
module mlxf_toy_projector
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf_toy_projector_workspace, only: projector_workspace
implicit none

public :: projector
private

! SIMPLE's members under SIMPLE's names, for the members the toy has: the logical dimensions, the sampling
! distance, the real volume and whether the image is in Fourier space (ft). The toy's own: pad_s, the seconds of
! the pad_fft calls that filled this projector; existence; ws, the device state (SIMPLE's cmat_exp is in it)
type :: projector
    private
    integer                           :: ldim(3)   = 0
    real(real32)                      :: smpd      = 0._real32
    logical                           :: ft        = .false.
    logical                           :: existence = .false.
    real(real64)                      :: pad_s     = 0._real64
    real(real32), allocatable         :: rmat(:,:,:)
    type(projector_workspace), public :: ws
  contains
    procedure :: new
    procedure :: set_rmat
    procedure :: get_cmat
    procedure :: pad_fft
    procedure :: expand_cmat
    procedure :: is_expanded
    procedure :: kill_expanded
    procedure :: kill
    procedure :: set_fproject_form
    procedure :: set_fproject_tile
    procedure :: fproject_seconds
    procedure :: message
    final     :: projector_final
end type projector

contains

    ! a cubic volume of even side ldim(1) at sampling distance smpd, all zero; a refusal (message) leaves no projector
    subroutine new( self, ldim, smpd )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: ldim(3)
        real(real32),     intent(in)    :: smpd
        call self%kill()
        if( any(ldim /= ldim(1)) .or. ldim(1) < 2 .or. mod(ldim(1), 2) /= 0 )then
            call self%ws%set_message('projector%new: refused: the toy projects cubes of even side')
            return
        endif
        self%ldim = ldim
        self%smpd = smpd
        allocate(self%rmat(ldim(1), ldim(2), ldim(3)), source=0._real32)
        self%existence = .true.
    end subroutine new

    ! the real volume: the leading ldim of rmat, the rest zero; ft says whether it is a transform (SIMPLE's flag)
    subroutine set_rmat( self, rmat, ft )
        class(projector), intent(inout) :: self
        real(real32),     intent(in)    :: rmat(:,:,:)
        logical,          intent(in)    :: ft
        call self%ws%set_message('')
        if( .not. self%existence )then
            call self%ws%set_message('projector%set_rmat: refused: no projector (new)')
            return
        endif
        if( any(shape(rmat) < self%ldim) )then
            call self%ws%set_message('projector%set_rmat: refused: rmat is smaller than the volume')
            return
        endif
        self%rmat = rmat(:self%ldim(1), :self%ldim(2), :self%ldim(3))
        self%ft   = ft
    end subroutine set_rmat

    ! the padded transform (M/2+1, M, M) of a padded projector, copied from the device between pad_fft and
    ! expand_cmat; of size zero on a refusal (message)
    function get_cmat( self ) result(cmat)
        class(projector), intent(inout) :: self
        complex(real32), allocatable :: cmat(:,:,:)
        integer                      :: st
        call self%ws%set_message('')
        call self%ws%copy_transform(cmat, st)
        if( st /= 0 )then
            if( allocated(cmat) ) deallocate(cmat)
            allocate(cmat(0, 0, 0))
        endif
    end function get_cmat

    ! this volume padded into self_out's box (centred: the origin, voxel N/2 + 1, at voxel 1 of the padded box)
    ! and transformed there: self_out holds the (M/2+1, M, M) half spectrum divided by M**3
    subroutine pad_fft( self, self_out )
        class(projector), intent(in)    :: self
        class(projector), intent(inout) :: self_out
        integer(int64) :: t0, t1, rate
        integer        :: n, m, i, j, k, st
        call self_out%ws%set_message('')
        if( .not. self%existence .or. .not. self_out%existence )then
            call self_out%ws%set_message('projector%pad_fft: refused: no projector (new)')
            return
        endif
        n = self%ldim(1)
        m = self_out%ldim(1)
        if( m < n )then
            call self_out%ws%set_message('projector%pad_fft: refused: the padded box is smaller than the volume')
            return
        endif
        call system_clock(t0)
        call self_out%kill_expanded()
        ! the padded real cube is staged in self_out's own volume, as SIMPLE's is before its in-place transform
        self_out%rmat = 0._real32
        do k = 1, n
            do j = 1, n
                do i = 1, n
                    self_out%rmat(1 + modulo(i - 1 - n / 2, m), 1 + modulo(j - 1 - n / 2, m), &
                        &1 + modulo(k - 1 - n / 2, m)) = self%rmat(i, j, k)
                end do
            end do
        end do
        call self_out%ws%transform(self_out%rmat, st)
        self_out%ft = st == 0
        call system_clock(t1, rate)
        self_out%pad_s = self_out%pad_s + real(t1 - t0, real64) / real(rate, real64)
    end subroutine pad_fft

    ! the expanded cube from the padded transform (SIMPLE's cmat_exp, in ws), evaluated; the transform is not kept
    subroutine expand_cmat( self )
        class(projector), intent(inout) :: self
        integer :: st
        call self%ws%set_message('')
        if( .not. self%existence )then
            call self%ws%set_message('projector%expand_cmat: refused: no projector (new)')
            return
        endif
        call self%ws%expand(st)
    end subroutine expand_cmat

    pure logical function is_expanded( self )
        class(projector), intent(in) :: self
        is_expanded = self%ws%has_cube()
    end function is_expanded

    subroutine kill_expanded( self )
        class(projector), intent(inout) :: self
        call self%ws%kill_cube()
    end subroutine kill_expanded

    ! idempotent teardown: the workspace (transform, cube, kernels) and the volume
    subroutine kill( self )
        class(projector), intent(inout) :: self
        call self%ws%kill()
        if( allocated(self%rmat) ) deallocate(self%rmat)
        self%ldim      = 0
        self%smpd      = 0._real32
        self%ft        = .false.
        self%pad_s     = 0._real64
        self%existence = .false.
    end subroutine kill

    subroutine projector_final( self )
        type(projector), intent(inout) :: self
        call self%kill()
    end subroutine projector_final

    ! the form of the polar gather (PROJ_FORMS): the graph, or the fused Metal kernel (GPU only)
    subroutine set_fproject_form( self, form )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: form
        call self%ws%set_form(form)
    end subroutine set_fproject_form

    ! the directions of one tile of the gather, and the fused kernel's threads per threadgroup
    subroutine set_fproject_tile( self, tile, tg )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: tile, tg
        call self%ws%set_tile(tile, tg)
    end subroutine set_fproject_tile

    ! the accumulated seconds of this projector's stages: pad and transform, expansion, projection
    pure function fproject_seconds( self ) result(t)
        class(projector), intent(in) :: self
        real(real64) :: t(3)
        t(1)   = self%pad_s
        t(2:3) = self%ws%seconds()
    end function fproject_seconds

    ! the reason the last call was refused, or an empty string
    pure function message( self ) result(msg)
        class(projector), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = self%ws%message()
    end function message

end module mlxf_toy_projector
