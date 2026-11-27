!@descr: the toy's neighbourhood utilities (test only): the view distance of SIMPLE's cone test, in c1 and without the mirror view
! SIMPLE's cone_view_dist minimises the angle between two projection directions over the point group and, with
! the mirror, over the seed's mirror view. The toy is c1 without the mirror: the angle between two unit vectors
! in degrees, in double precision, the dot product clipped to [-1, 1]. Plain host code on both backends.
module mlxf_toy_eul_prob_tab_utils
use, intrinsic :: iso_fortran_env, only: real64
implicit none

public :: cone_view_dist
private

contains

    ! the view distance (degrees) of direction v from the seed direction v_seed, both unit vectors
    pure real(real64) function cone_view_dist( v_seed, v ) result(dist)
        real(real64), intent(in) :: v_seed(3), v(3)
        dist = acos(max(-1._real64, min(1._real64, dot_product(v_seed, v)))) * 180._real64 / acos(-1._real64)
    end function cone_view_dist

end module mlxf_toy_eul_prob_tab_utils
