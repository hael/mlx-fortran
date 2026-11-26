!@descr: the toy projector (test only): a miniature of SIMPLE's projector with the image procedures the reprojection calls
! The type and its procedures carry SIMPLE's names (projector, with new, set_rmat, pad_fft and kill of the image it
! extends in SIMPLE); scripts/toy_mirror.txt lists each as mirrored or as an addition. The host holds the real
! volume rmat (N, N, N), voxel i at the centred x = i - 1 - N/2. pad_fft writes it into a padded box of side M
! with its origin at voxel 1 (SIMPLE's fused pad and fftshift) and hands it to the padded projector's device
! state, which transforms it; expand_cmat makes SIMPLE's expanded cube there. All MLX state is the component ws,
! made with the projector and released in kill; this module sees it as class(device_work) and imports no MLX
! name, and the glue submodule mlxf_toy_projector_mlx holds what needs the device. The toy has no host route: a
! projector is made on the MLX backend or refused.
module mlxf_toy_projector
use, intrinsic :: iso_fortran_env, only: int64, real32, real64
use mlxf_test_defs,       only: parameters
use mlxf_toy_device_work, only: device_work
implicit none

public :: projector
private

! SIMPLE's members under SIMPLE's names, for the members the toy has: the logical dimensions, the sampling
! distance, the real volume and whether the image is in Fourier space (ft). The toy's own: pad_s, the seconds of
! the pad_fft calls that filled this projector; existence; l_mlx, the backend taken at new; msg, the reason of the
! last refusal; ws, the device state (SIMPLE's cmat_exp is in it), public as cmat_exp is
type :: projector
    private
    integer                                 :: ldim(3)   = 0
    real(real32)                            :: smpd      = 0._real32
    logical                                 :: ft        = .false.
    logical                                 :: existence = .false.
    logical                                 :: l_mlx     = .false.
    real(real64)                            :: pad_s     = 0._real64
    real(real32),       allocatable         :: rmat(:,:,:)
    character(len=:),   allocatable         :: msg
    class(device_work), allocatable, public :: ws
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
    procedure :: set_message
    procedure :: message
    final     :: projector_final
end type projector

! MLX: the glue procedures, private to the class. A host procedure's whole knowledge of the device is a guarded
! call of its <name>_mlx; the bodies are in the glue submodule mlxf_toy_projector_mlx, which alone imports the
! workspace, and which a build without MLX compiles as stubs that refuse with "built without MLX"
interface
    ! the device state of a new projector
    module subroutine new_mlx( self, status )
        class(projector), intent(inout) :: self
        integer,          intent(out)   :: status
    end subroutine new_mlx

    ! the padded transform copied from the device, while it is held
    module subroutine get_cmat_mlx( self, cmat, status )
        class(projector),             intent(inout) :: self
        complex(real32), allocatable, intent(out)   :: cmat(:,:,:)
        integer,                      intent(out)   :: status
    end subroutine get_cmat_mlx

    ! the padded real cube staged in self_out's volume, uploaded and transformed on the device
    module subroutine pad_fft_mlx( self_out, status )
        class(projector), intent(inout) :: self_out
        integer,          intent(out)   :: status
    end subroutine pad_fft_mlx

    ! the expanded cube from the padded transform, on the device
    module subroutine expand_cmat_mlx( self )
        class(projector), intent(inout) :: self
    end subroutine expand_cmat_mlx

    pure module logical function is_expanded_mlx( self )
        class(projector), intent(in) :: self
    end function is_expanded_mlx

    module subroutine kill_expanded_mlx( self )
        class(projector), intent(inout) :: self
    end subroutine kill_expanded_mlx

    module subroutine set_fproject_form_mlx( self, form )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: form
    end subroutine set_fproject_form_mlx

    module subroutine set_fproject_tile_mlx( self, tile, tg )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: tile, tg
    end subroutine set_fproject_tile_mlx

    ! the accumulated seconds of the expansions and of the projections
    pure module function fproject_seconds_mlx( self ) result(t)
        class(projector), intent(in) :: self
        real(real64) :: t(2)
    end function fproject_seconds_mlx
end interface

contains

    ! a cubic volume of even side ldim(1) at sampling distance smpd, all zero, on the backend params%l_mlx names (the
    ! MLX one when params is absent); a refusal (message) leaves no projector. The toy has no host route.
    subroutine new( self, ldim, smpd, params )
        class(projector),           intent(inout) :: self
        integer,                    intent(in)    :: ldim(3)
        real(real32),               intent(in)    :: smpd
        type(parameters), optional, intent(in)    :: params
        integer :: st
        call self%kill()
        if( any(ldim /= ldim(1)) .or. ldim(1) < 2 .or. mod(ldim(1), 2) /= 0 )then
            self%msg = 'projector%new: refused: the toy projects cubes of even side'
            return
        endif
        self%l_mlx = .true.
        if( present(params) ) self%l_mlx = params%l_mlx
        if( .not. self%l_mlx )then
            self%msg = 'projector%new: refused: the toy has no host route'
            return
        endif
        call new_mlx(self, st)
        if( st /= 0 )then
            self%l_mlx = .false.
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
        self%msg = ''
        if( .not. self%existence )then
            self%msg = 'projector%set_rmat: refused: no projector (new)'
            return
        endif
        if( any(shape(rmat) < self%ldim) )then
            self%msg = 'projector%set_rmat: refused: rmat is smaller than the volume'
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
        self%msg = ''
        st       = 1
        if( self%l_mlx )then
            call get_cmat_mlx(self, cmat, st)
        else
            self%msg = 'projector%get_cmat: refused: no padded transform (pad_fft, before expand_cmat)'
        endif
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
        self_out%msg = ''
        if( .not. self%existence .or. .not. self_out%existence )then
            self_out%msg = 'projector%pad_fft: refused: no projector (new)'
            return
        endif
        n = self%ldim(1)
        m = self_out%ldim(1)
        if( m < n )then
            self_out%msg = 'projector%pad_fft: refused: the padded box is smaller than the volume'
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
        st = 1
        if( self_out%l_mlx ) call pad_fft_mlx(self_out, st)
        self_out%ft = st == 0
        call system_clock(t1, rate)
        self_out%pad_s = self_out%pad_s + real(t1 - t0, real64) / real(rate, real64)
    end subroutine pad_fft

    ! the expanded cube from the padded transform (SIMPLE's cmat_exp, in ws), evaluated; the transform is not kept
    subroutine expand_cmat( self )
        class(projector), intent(inout) :: self
        self%msg = ''
        if( .not. self%existence )then
            self%msg = 'projector%expand_cmat: refused: no projector (new)'
            return
        endif
        if( self%l_mlx ) call expand_cmat_mlx(self)
    end subroutine expand_cmat

    pure logical function is_expanded( self )
        class(projector), intent(in) :: self
        is_expanded = .false.
        if( self%l_mlx ) is_expanded = is_expanded_mlx(self)
    end function is_expanded

    subroutine kill_expanded( self )
        class(projector), intent(inout) :: self
        if( self%l_mlx ) call kill_expanded_mlx(self)
    end subroutine kill_expanded

    ! idempotent teardown: the device state (transform, cube, kernels), killed before it is deallocated, and the
    ! volume
    subroutine kill( self )
        class(projector), intent(inout) :: self
        if( allocated(self%ws) )then
            call self%ws%kill()
            deallocate(self%ws)
        endif
        if( allocated(self%rmat) ) deallocate(self%rmat)
        self%ldim      = 0
        self%smpd      = 0._real32
        self%ft        = .false.
        self%pad_s     = 0._real64
        self%msg       = ''
        self%l_mlx     = .false.
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
        if( self%l_mlx )then
            call set_fproject_form_mlx(self, form)
        else
            self%msg = 'projector%set_fproject_form: refused: no projector (new)'
        endif
    end subroutine set_fproject_form

    ! the directions of one tile of the gather, and the fused kernel's threads per threadgroup
    subroutine set_fproject_tile( self, tile, tg )
        class(projector), intent(inout) :: self
        integer,          intent(in)    :: tile, tg
        if( self%l_mlx )then
            call set_fproject_tile_mlx(self, tile, tg)
        else
            self%msg = 'projector%set_fproject_tile: refused: no projector (new)'
        endif
    end subroutine set_fproject_tile

    ! the accumulated seconds of this projector's stages: pad and transform, expansion, projection
    pure function fproject_seconds( self ) result(t)
        class(projector), intent(in) :: self
        real(real64) :: t(3)
        t(1)   = self%pad_s
        t(2:3) = 0._real64
        if( self%l_mlx ) t(2:3) = fproject_seconds_mlx(self)
    end function fproject_seconds

    ! the batch projector keeps its refusals with the projector's own, so that one message() reports either
    subroutine set_message( self, msg )
        class(projector), intent(inout) :: self
        character(len=*), intent(in)    :: msg
        self%msg = msg
    end subroutine set_message

    ! the reason the last call was refused, or an empty string
    pure function message( self ) result(msg)
        class(projector), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

end module mlxf_toy_projector
