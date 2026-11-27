!@descr: the toy search-space map (test only): SIMPLE's srchspace_map, a full space of directions mapped to the cells of a subspace
! As SIMPLE's new_from_distmat: from the distances of every subspace point (rows) to every full-space point
! (columns), a full-space point's cell is its nearest subspace point and a cell's representative the nearest
! full-space point, the first of equal distances. Plain host code on both backends.
module mlxf_toy_srchspace_map
implicit none

public :: srchspace_map
private

! SIMPLE's members: the spaces' sizes, each full-space point's cell and each cell's representative; the reason of
! the last refusal (SIMPLE stops where the toy refuses)
type :: srchspace_map
    private
    integer                       :: nspace = 0
    integer                       :: nsub   = 0
    integer,          allocatable :: full2sub_map(:)
    integer,          allocatable :: sub2full_map(:)
    character(len=:), allocatable :: msg
  contains
    procedure :: new
    procedure :: get_sub2full_map
    procedure :: get_full2sub_map
    procedure :: message
    procedure :: kill
end type srchspace_map

contains

    ! the map of nspace points to nspace_sub cells from distmat (cells, points); a refusal (message) leaves no map
    subroutine new( self, nspace, nspace_sub, distmat )
        class(srchspace_map), intent(inout) :: self
        integer,              intent(in)    :: nspace, nspace_sub
        real,                 intent(in)    :: distmat(nspace_sub, nspace)
        call self%kill()
        if( nspace < 1 .or. nspace_sub < 1 .or. nspace_sub > nspace )then
            self%msg = 'srchspace_map%new: refused: 1 <= nspace_sub <= nspace'
            return
        endif
        self%nspace       = nspace
        self%nsub         = nspace_sub
        self%full2sub_map = minloc(distmat, dim=1)
        self%sub2full_map = minloc(distmat, dim=2)
    end subroutine new

    ! each cell's representative (an empty array without a map)
    pure function get_sub2full_map( self ) result(arr)
        class(srchspace_map), intent(in) :: self
        integer, allocatable :: arr(:)
        allocate(arr(0))
        if( allocated(self%sub2full_map) ) arr = self%sub2full_map
    end function get_sub2full_map

    ! each point's cell (an empty array without a map)
    pure function get_full2sub_map( self ) result(arr)
        class(srchspace_map), intent(in) :: self
        integer, allocatable :: arr(:)
        allocate(arr(0))
        if( allocated(self%full2sub_map) ) arr = self%full2sub_map
    end function get_full2sub_map

    ! the reason the last call was refused, or an empty string
    pure function message( self ) result(msg)
        class(srchspace_map), intent(in) :: self
        character(len=:), allocatable :: msg
        msg = ''
        if( allocated(self%msg) ) msg = self%msg
    end function message

    ! idempotent: the map released
    subroutine kill( self )
        class(srchspace_map), intent(inout) :: self
        if( allocated(self%full2sub_map) ) deallocate(self%full2sub_map)
        if( allocated(self%sub2full_map) ) deallocate(self%sub2full_map)
        self%nspace = 0
        self%nsub   = 0
        self%msg    = ''
    end subroutine kill

end module mlxf_toy_srchspace_map
