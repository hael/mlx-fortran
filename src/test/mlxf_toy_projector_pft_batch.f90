!@descr: the toy batch projector (test only): SIMPLE's fproject_polar_batch_opt, the projection of a state's reference bank
! As SIMPLE's: the calculator's polar coordinates times the padding factor (hkcoords), the first two rows of
! every direction's rotation matrix (rotmats), and the gather of every (direction, shell, angle) sample from the
! expanded cube of vol_pad. The gather is the projector workspace's, in the form vol_pad was set to. The bank
! comes back to the host in refs_state (pftsz, nk, nspace) or, by the resident form (an addition), stays on the
! device for the calculator's device route. scripts/toy_mirror.txt lists both.
module mlxf_toy_projector_pft_batch
use, intrinsic :: iso_fortran_env, only: real32
use mlxf,                  only: mlx_array, mlx_to, reshape
use mlxf_test_defs,        only: OSMPL_PAD_FAC, fproject_spec
use mlxf_toy_projector,    only: projector
use mlxf_toy_polarft_calc, only: polarft_calc
implicit none

public :: fproject_polar_batch_opt, fproject_polar_batch_resident
private

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
        type(mlx_array)     :: bank
        integer             :: st
        refs_state = cmplx(0._real32, 0._real32, real32)
        spec%nspace     = nspace
        spec%refs_shape = shape(refs_state)
        call project_bank(vol_pad, eulspace, pftc, spec, bank)
        if( len(vol_pad%message()) > 0 ) return
        call mlx_to(refs_state, reshape(bank, shape(refs_state)), status=st)
        if( st /= 0 )then
            call vol_pad%ws%set_message('fproject_polar_batch_opt: the bank could not be copied to the host')
            refs_state = cmplx(0._real32, 0._real32, real32)
        endif
    end subroutine fproject_polar_batch_opt

    ! the same bank left on the device, evaluated, as (pftsz nk, nspace); a refusal leaves bank empty
    subroutine fproject_polar_batch_resident( vol_pad, eulspace, nspace, pftc, bank )
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        integer,             intent(in)    :: nspace
        class(polarft_calc), intent(inout) :: pftc
        type(mlx_array),     intent(out)   :: bank
        type(fproject_spec) :: spec
        integer             :: kfromto(2)
        kfromto         = pftc%get_kfromto()
        spec%nspace     = nspace
        spec%refs_shape = [pftc%get_pftsz(), kfromto(2) - kfromto(1) + 1, nspace]
        call project_bank(vol_pad, eulspace, pftc, spec, bank)
    end subroutine fproject_polar_batch_resident

    ! SIMPLE's preparation: the padded polar coordinates (2, pftsz, nk) and the rotation rows (2, 3, nspace), then
    ! the workspace's gather of spec%nspace directions into a bank whose host shape would be spec%refs_shape
    subroutine project_bank( vol_pad, eulspace, pftc, spec, bank )
        class(projector),    intent(inout) :: vol_pad
        real(real32),        intent(in)    :: eulspace(:,:,:)
        class(polarft_calc), intent(inout) :: pftc
        type(fproject_spec), intent(inout) :: spec
        type(mlx_array),     intent(out)   :: bank
        real(real32), allocatable :: tmp(:,:), rotmats(:,:,:), hkcoords(:,:,:)
        integer                   :: kfromto(2), iproj, st, nspace
        call vol_pad%ws%set_message('')
        kfromto = pftc%get_kfromto()
        spec%pftsz      = pftc%get_pftsz()
        spec%nk         = kfromto(2) - kfromto(1) + 1
        spec%kto        = kfromto(2)
        spec%noris      = size(eulspace, 3)
        nspace          = spec%nspace
        if( kfromto(1) < 1 .or. kfromto(1) > kfromto(2) .or. spec%pftsz < 1 )then
            call vol_pad%ws%set_message('fproject_polar_batch_opt: refused: invalid kfromto')
            return
        endif
        if( size(eulspace, 1) /= 3 .or. size(eulspace, 2) /= 3 )then
            call vol_pad%ws%set_message('fproject_polar_batch_opt: refused: eulspace holds 3 by 3 rotation matrices')
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
        call vol_pad%ws%project(spec, bank, st)
    end subroutine project_bank

end module mlxf_toy_projector_pft_batch
