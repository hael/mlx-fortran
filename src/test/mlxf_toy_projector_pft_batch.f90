!@descr: the toy batch projector (test only): SIMPLE's fproject_polar_batch_opt, the projection of a state's reference bank
! As SIMPLE's: the calculator's polar coordinates times the padding factor (hkcoords), the first two rows of
! every direction's rotation matrix (rotmats), and the gather of every (direction, shell, angle) sample from the
! expanded cube of vol_pad. The preparation is host code; the gather is the projector's device state's, in the
! form vol_pad was set to, and the glue submodule mlxf_toy_projector_pft_batch_mlx reaches it. The bank comes
! back to the host in refs_state (pftsz, nk, nspace) or, by the resident form (an addition), stays on the device
! as an opaque object for the calculator's device route. scripts/toy_mirror.txt lists both.
module mlxf_toy_projector_pft_batch
use, intrinsic :: iso_fortran_env, only: real32
use mlxf_test_defs,        only: OSMPL_PAD_FAC, fproject_spec
use mlxf_toy_device_work,  only: device_work
use mlxf_toy_projector,    only: projector
use mlxf_toy_polarft_calc, only: polarft_calc
implicit none

public :: fproject_polar_batch_opt, fproject_polar_batch_resident
private

! MLX: the glue procedures, private to the module; the bodies are in the glue submodule
! mlxf_toy_projector_pft_batch_mlx, which a build without MLX compiles as stubs that refuse
interface
    ! the gather of spec's directions from vol_pad's expanded cube, copied to the host
    module subroutine fproject_polar_batch_opt_mlx( vol_pad, spec, refs_state )
        class(projector),    intent(inout) :: vol_pad
        type(fproject_spec), intent(in)    :: spec
        complex(real32),     intent(inout) :: refs_state(:,:,:)
    end subroutine fproject_polar_batch_opt_mlx

    ! the same gather left on the device: bank holds the evaluated sections (pftsz nk, nspace)
    module subroutine fproject_polar_batch_resident_mlx( vol_pad, spec, bank )
        class(projector),                intent(inout) :: vol_pad
        type(fproject_spec),             intent(in)    :: spec
        class(device_work), allocatable, intent(out)   :: bank
    end subroutine fproject_polar_batch_resident_mlx
end interface

contains

    ! the bank of nspace references of one state, (irot, k - kfromto(1) + 1, iproj), from the expanded vol_pad under
    ! the rotation matrices eulspace(:, :, iproj); a refusal (vol_pad%message()) leaves refs_state at zero
    subroutine fproject_polar_batch_opt( vol_pad, eulspace, nspace, pftc, refs_state )
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        integer,             intent(in)    :: nspace
        class(polarft_calc), intent(inout) :: pftc
        complex(real32),     intent(inout) :: refs_state(:,:,:)
        type(fproject_spec) :: spec
        refs_state = cmplx(0._real32, 0._real32, real32)
        spec%nspace     = nspace
        spec%refs_shape = shape(refs_state)
        call projection_spec(vol_pad, eulspace, pftc, spec)
        if( len(vol_pad%message()) > 0 ) return
        ! the device state exists on the MLX backend only, and the toy has no host route
        if( allocated(vol_pad%ws) )then
            call fproject_polar_batch_opt_mlx(vol_pad, spec, refs_state)
        else
            call vol_pad%set_message('fproject_polar_batch_opt: refused: the projector is not expanded (expand_cmat)')
        endif
    end subroutine fproject_polar_batch_opt

    ! the same bank left on the device, evaluated, as (pftsz nk, nspace); a refusal leaves bank unallocated
    subroutine fproject_polar_batch_resident( vol_pad, eulspace, nspace, pftc, bank )
        class(projector),                intent(inout) :: vol_pad
        real(real32),                    intent(in)    :: eulspace(:,:,:)
        integer,                         intent(in)    :: nspace
        class(polarft_calc),             intent(inout) :: pftc
        class(device_work), allocatable, intent(out)   :: bank
        type(fproject_spec) :: spec
        integer             :: kfromto(2)
        kfromto         = pftc%get_kfromto()
        spec%nspace     = nspace
        spec%refs_shape = [pftc%get_pftsz(), kfromto(2) - kfromto(1) + 1, nspace]
        call projection_spec(vol_pad, eulspace, pftc, spec)
        if( len(vol_pad%message()) > 0 ) return
        if( allocated(vol_pad%ws) )then
            call fproject_polar_batch_resident_mlx(vol_pad, spec, bank)
        else
            call vol_pad%set_message('fproject_polar_batch_opt: refused: the projector is not expanded (expand_cmat)')
        endif
    end subroutine fproject_polar_batch_resident

    ! SIMPLE's preparation: the padded polar coordinates (2, pftsz, nk) and the rotation rows (2, 3, nspace) of
    ! spec%nspace directions, for a bank whose host shape would be spec%refs_shape; a refusal sets vol_pad's message
    subroutine projection_spec( vol_pad, eulspace, pftc, spec )
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        class(polarft_calc), intent(inout) :: pftc
        type(fproject_spec), intent(inout) :: spec
        real(real32), allocatable :: tmp(:,:), rotmats(:,:,:), hkcoords(:,:,:)
        integer                   :: kfromto(2), iproj, nspace
        call vol_pad%set_message('')
        kfromto = pftc%get_kfromto()
        spec%pftsz      = pftc%get_pftsz()
        spec%nk         = kfromto(2) - kfromto(1) + 1
        spec%kto        = kfromto(2)
        spec%noris      = size(eulspace, 3)
        nspace          = spec%nspace
        if( kfromto(1) < 1 .or. kfromto(1) > kfromto(2) .or. spec%pftsz < 1 )then
            call vol_pad%set_message('fproject_polar_batch_opt: refused: invalid kfromto')
            return
        endif
        if( size(eulspace, 1) /= 3 .or. size(eulspace, 2) /= 3 )then
            call vol_pad%set_message('fproject_polar_batch_opt: refused: eulspace holds 3 by 3 rotation matrices')
            return
        endif
        allocate(tmp(kfromto(1):kfromto(2), spec%pftsz), rotmats(2, 3, max(nspace, 0)), &
            &hkcoords(2, spec%pftsz, spec%nk))
        ! format polar coordinates, padded
        call pftc%get_polar_coords(1, tmp)
        hkcoords(1, :,:) = transpose(tmp)
        call pftc%get_polar_coords(2, tmp)
        hkcoords(2, :,:) = transpose(tmp)
        deallocate(tmp)
        hkcoords = real(OSMPL_PAD_FAC, real32) * hkcoords
        ! format rotation matrices
        do iproj = 1, min(nspace, spec%noris)
            rotmats(:, :, iproj) = eulspace(1:2, :, iproj)
        end do
        spec%hk  = reshape(hkcoords, [2, spec%pftsz * spec%nk])
        spec%rot = rotmats
    end subroutine projection_spec

end module mlxf_toy_projector_pft_batch
