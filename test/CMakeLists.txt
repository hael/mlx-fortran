# test/CMakeLists.txt
#
# mlxf_test_exec, the one test executable: its program, the test-only sources of src/ (src/test/ and the
# *_tester.f90 beside the modules they test; src/CMakeLists.txt keeps them out of the library) and the
# CTest entries. Its modules go to their own directory, so installing the library never installs one.
#
# Checks are free, processes are budgeted (XEMA): a CTest entry is an isolation unit, not an assertion.
# Checks grow inside the existing area suites (src/test/mlxf_test_registry.f90); a new entry needs a
# reason in its registration comment and raises MLXF_CTEST_BUDGET below, which configuration holds to the
# registered count. The budget changes only with an owner decision or a plan that names the entry.
# scripts/check_test_registry.py holds the areas here and in the registry to each other. The fast label as
# a whole stays under 60 s of real time (scripts/run_fast_gate.sh); an entry above 0.5 s in Release says
# why in its registration comment.

add_executable(mlxf_test_exec "${CMAKE_CURRENT_SOURCE_DIR}/mlxf_test_exec.f90" ${MLXF_TEST_ONLY_SOURCES})
set(_moddir "${PROJECT_BINARY_DIR}/modules/mlxf_test_exec")
file(MAKE_DIRECTORY "${_moddir}")
set_target_properties(mlxf_test_exec PROPERTIES
    LINKER_LANGUAGE          Fortran
    Fortran_MODULE_DIRECTORY "${_moddir}")
target_include_directories(mlxf_test_exec PRIVATE "${MLXF_GEN_DIR}")
target_link_libraries(mlxf_test_exec PRIVATE mlxf mlxf_build_flags)
# MLXF_REQUIRE_GPU (CMakeLists.txt) is a compile definition, not an environment variable: the library and its
# tests read no variable of their own. With it, a session that cannot open a GPU fails the device tests.
if(MLXF_REQUIRE_GPU)
    target_compile_definitions(mlxf_test_exec PRIVATE MLXF_REQUIRE_GPU)
endif()
install(TARGETS mlxf_test_exec RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

set(MLXF_TEST_RUNS_DIR "${CMAKE_BINARY_DIR}/test_runs")

# mlxf_add_test(<name> <label> <timeout> COMMAND <args...>): runs in its own directory under test_runs/
# on one OpenMP thread, with MLX's float32 matrix products in full precision (MLX_ENABLE_TF32=0: on GPUs
# with matrix units MLX otherwise computes them at reduced precision, and the tolerances assume float32).
function(mlxf_add_test name label timeout)
    cmake_parse_arguments(ARG "" "" "COMMAND" ${ARGN})
    file(MAKE_DIRECTORY "${MLXF_TEST_RUNS_DIR}/${name}")
    add_test(NAME ${name} COMMAND ${ARG_COMMAND} WORKING_DIRECTORY "${MLXF_TEST_RUNS_DIR}/${name}")
    set_tests_properties(${name} PROPERTIES
        LABELS "${label}"
        TIMEOUT ${timeout}
        ENVIRONMENT "OMP_NUM_THREADS=1;OMP_WAIT_POLICY=PASSIVE;OMP_THREAD_LIMIT=4;GFORTRAN_UNBUFFERED_ALL=y;MLX_ENABLE_TF32=0")
endfunction()

# ---- the fast gate: one entry per area suite -------------------------------------------------------
# An explicit TIMEOUT overrides ctest --timeout; keep it in sync with scripts/run_fast_gate.sh.
# unit_core: its recovery gate fails, per device, a graph one buffer beyond the GPU's maximum (refused before
#   allocating) and evaluates the same graph at 1 GiB; the half-batch form, half the GPU's maximum buffer
#   (64.9 GB on a 192 GB M2 Ultra), is the sub-suite recovery_half, run by name only.
# unit_array (above 0.5 s, the area named by the design plan): its leak gate runs 10,000 iterations of every
#   supported form of the handle model per device.
# ops, linalg and fft isolate the operation families and run independent CPU/GPU oracles.
# compile isolates callback tracing, checked callback failures and shapeless reuse on both devices.
# Cold CPU/GPU JIT compilation can put it above 0.5 s; cached invocations are much shorter.
# kernels: test-only models of SIMPLE's pipelines (the polar table's scoring
#   workspace and its shift maps) on seeded or analytic fixtures against double-precision oracles, on both
#   devices; its own process keeps the workspace's lifecycle checks (live count and active memory back to warm
#   values) apart from other areas. Above 0.5 s in Release: the oracles' direct sums over every rotation and
#   cell, and the GPU's first compilation of its kernels.
set(MLXF_TEST_AREAS core array ops linalg fft compile kernels)
foreach(_area IN LISTS MLXF_TEST_AREAS)
    mlxf_add_test(unit_${_area} fast 600 COMMAND $<TARGET_FILE:mlxf_test_exec> test=unit_${_area})
endforeach()

# ---- guard groups: stops that are the contract, each member in a child (expect_aborts) ----------------
# object_contracts: an operation on an empty array, a stale handle used, a call inside an OpenMP region, a
#   float64 operation built on the GPU, and the one-thread guard on the paths that touch no operand (an empty
#   evaluation list, mlx_live_count, mlx_last_error) and on a live private copy released in a region; a
#   invalid 1D/2D FFT normalizations; a separate entry because every member ends its process.
mlxf_add_test(object_contracts fast 600 COMMAND $<TARGET_FILE:mlxf_test_exec> expect_aborts object_contracts)

# ---- the budget ----------------------------------------------------------------------------------
set(MLXF_CTEST_BUDGET 8)
get_property(_mlxf_tests DIRECTORY PROPERTY TESTS)
list(LENGTH _mlxf_tests _mlxf_ntests)
if(NOT _mlxf_ntests EQUAL MLXF_CTEST_BUDGET)
    message(FATAL_ERROR "${_mlxf_ntests} CTest entries do not match the budget of ${MLXF_CTEST_BUDGET} "
        "(test/CMakeLists.txt): add checks to an existing area suite, or justify the new process and raise the "
        "budget with the owner's or the plan's decision")
endif()
