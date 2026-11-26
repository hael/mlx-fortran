!@descr: the toy PCG engine's record (test only): SIMPLE's pcg_solver_outcome of simple_pcg_solver, with its kill
! The host half of the engine's miniature: the facts of a solve, which a class's host procedures hand back (the
! reconstructor's solve_accum). It imports no MLX name and compiles without the library. The engine that fills the
! record runs on device vectors and is the device module mlxf_toy_pcg_solver_mlx, with SIMPLE's abstract operator;
! SIMPLE's host engine is not modelled.
module mlxf_toy_pcg_solver
use, intrinsic :: iso_fortran_env, only: real32, real64
implicit none

public :: pcg_solver_outcome
private

! SIMPLE's solver facts, for the members the toy keeps: the reason (also a refusal's), the iterations done and
! asked for, the first and last relative residuals and the last relative update, an indefinite product and its
! iteration, convergence, a rejected start, |b| and |x0|, and per iteration the residual, the update and seconds
type :: pcg_solver_outcome
    character(len=24)         :: stop_reason          = 'not_started'
    integer                   :: iteration_count      = 0
    integer                   :: requested_maxits     = 0
    real(real32)              :: initial_rel_residual = 0._real32
    real(real32)              :: final_rel_residual   = 0._real32
    real(real32)              :: final_rel_update     = 0._real32
    real(real64)              :: failure_curvature    = 0._real64
    integer                   :: failure_iteration    = 0
    logical                   :: converged            = .false.
    logical                   :: start_rejected       = .false.
    real(real32)              :: rhs_norm             = 0._real32
    real(real32)              :: start_norm           = 0._real32
    real(real32), allocatable :: rel_residual_history(:)
    real(real32), allocatable :: rel_update_history(:)
    real(real32), allocatable :: iteration_seconds(:)
  contains
    procedure :: kill => pcg_solver_outcome_kill
end type pcg_solver_outcome

contains

    ! back to the state of a new record
    subroutine pcg_solver_outcome_kill( self )
        class(pcg_solver_outcome), intent(inout) :: self
        if( allocated(self%rel_residual_history) ) deallocate(self%rel_residual_history)
        if( allocated(self%rel_update_history) ) deallocate(self%rel_update_history)
        if( allocated(self%iteration_seconds) ) deallocate(self%iteration_seconds)
        self%stop_reason          = 'not_started'
        self%iteration_count      = 0
        self%requested_maxits     = 0
        self%initial_rel_residual = 0._real32
        self%final_rel_residual   = 0._real32
        self%final_rel_update     = 0._real32
        self%failure_curvature    = 0._real64
        self%failure_iteration    = 0
        self%converged            = .false.
        self%start_rejected       = .false.
        self%rhs_norm             = 0._real32
        self%start_norm           = 0._real32
    end subroutine pcg_solver_outcome_kill

end module mlxf_toy_pcg_solver
