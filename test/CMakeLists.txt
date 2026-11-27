# test/CMakeLists.txt
#
# mlxf_test_exec, the one test executable: its program, the test-only sources of src/ (src/test/ and the
# *_tester.f90 beside the modules they test; src/CMakeLists.txt keeps them out of the library) and the
# CTest entries. Its modules go to their own directory, so installing the library never installs one.
#
# Checks are free, processes are budgeted (XEMA): a CTest entry is an isolation unit, not an assertion.
# Checks grow inside the existing area suites (src/test/framework/mlxf_test_registry.f90); a new entry needs a
# reason in its registration comment and raises MLXF_CTEST_BUDGET below, which configuration holds to the
# registered count. The budget changes only with an owner decision or a plan that names the entry.
# scripts/check_test_registry.py holds the areas here and in the registry to each other. The fast label as
# a whole stays under 60 s of real time (scripts/run_fast_gate.sh); an entry above 0.5 s in Release says
# why in its registration comment.

# The ABI probe (unit_core, sub-suite abi): the interfaces of src/test/framework/mlxf_abi_probe.h, generated with the library's
# mapping table into gen_test/ (never the library's gen/), and its echo functions compiled by Apple's clang, the
# compiler of mlx-c, as an object of this executable: CMake's C compiler is GCC, whose ABI agrees with GNU Fortran's
# by construction. Elsewhere than macOS the C compiler of the build stands in for Apple's clang.
set(_probe_header "${PROJECT_SOURCE_DIR}/src/test/framework/mlxf_abi_probe.h")
set(_probe_c      "${PROJECT_SOURCE_DIR}/src/test/framework/mlxf_abi_probe.c")
set(_probe_dir    "${PROJECT_BINARY_DIR}/gen_test")
set(_probe_f90    "${_probe_dir}/mlxf_c_abi_probe.f90")
set(_probe_obj    "${_probe_dir}/mlxf_abi_probe.o")
file(MAKE_DIRECTORY "${_probe_dir}")
file(GLOB _probe_mlxc_headers CONFIGURE_DEPENDS "${MLX_C_INCLUDE_DIRS}/mlx/c/*.h")
add_custom_command(
    OUTPUT "${_probe_f90}"
    COMMAND "${MLXF_PYTHON3}" -I "${PROJECT_SOURCE_DIR}/scripts/gen_mlxc_bindings.py" "${MLX_C_INCLUDE_DIRS}"
            "${_probe_dir}" --probe "${_probe_header}"
    DEPENDS "${_probe_header}" "${PROJECT_SOURCE_DIR}/scripts/gen_mlxc_bindings.py" ${_probe_mlxc_headers}
    COMMENT "Generating the ABI probe's interfaces (mlxf_c_abi_probe)"
    VERBATIM)
if(APPLE)
    # the target of GNU's linker: the running macOS's major release, as scripts/build_mlx_deps.sh builds MLX for
    execute_process(COMMAND sw_vers -productVersion OUTPUT_VARIABLE _probe_macos OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REGEX REPLACE "^([0-9]+).*" "\\1.0" _probe_macos "${_probe_macos}")
    set(_probe_cc xcrun clang "-mmacosx-version-min=${_probe_macos}")
else()
    set(_probe_cc "${CMAKE_C_COMPILER}")
endif()
add_custom_command(
    OUTPUT "${_probe_obj}"
    COMMAND ${_probe_cc} -std=c11 -O1 -Wall -Wextra -Werror "-I${MLX_C_INCLUDE_DIRS}" -c "${_probe_c}" -o "${_probe_obj}"
    DEPENDS "${_probe_c}" "${_probe_header}" ${_probe_mlxc_headers}
    COMMENT "Compiling the ABI probe's echo functions with the compiler of mlx-c"
    VERBATIM)
set_source_files_properties("${_probe_obj}" PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)

add_executable(mlxf_test_exec "${CMAKE_CURRENT_SOURCE_DIR}/mlxf_test_exec.f90" ${MLXF_TEST_ONLY_SOURCES}
    "${_probe_f90}" "${_probe_obj}")
set(_moddir "${PROJECT_BINARY_DIR}/modules/mlxf_test_exec")
file(MAKE_DIRECTORY "${_moddir}")
set_target_properties(mlxf_test_exec PROPERTIES
    LINKER_LANGUAGE          Fortran
    Fortran_MODULE_DIRECTORY "${_moddir}")
# the library's own tests import its private modules (testers are submodules of the modules they test); a
# target that only links mlxf sees mlxf.mod alone (src/CMakeLists.txt)
target_include_directories(mlxf_test_exec PRIVATE "${PROJECT_BINARY_DIR}/modules/mlxf" "${MLXF_GEN_DIR}")
target_link_libraries(mlxf_test_exec PRIVATE mlxf mlxf_build_flags)
# MLXF_REQUIRE_GPU (CMakeLists.txt) is a compile definition, not an environment variable: the library and its
# tests read no variable of their own. With it, a session that cannot open a GPU fails the device tests.
if(MLXF_REQUIRE_GPU)
    target_compile_definitions(mlxf_test_exec PRIVATE MLXF_REQUIRE_GPU)
endif()
# USE_MLX: the glue submodules of the toys (src/test/toys/*/mlxf_toy_*_mlx.f90) hold their bodies under it and stubs
# beside them, as SIMPLE holds a device body under USE_OPENMP_OFFLOAD. This executable always has MLX; the project
# test/offstate compiles the same files without the definition and without the library.
target_compile_definitions(mlxf_test_exec PRIVATE USE_MLX)
# The BLAS crossover bench (test=bench_blas) times the host's sgemm and cgemm through CBLAS. On macOS the system's
# BLAS is Accelerate, linked to this executable only, never to the library; elsewhere, or when it is not found,
# MLXF_HAVE_BLAS stays undefined and the bench's host route is Fortran's matmul.
if(APPLE)
    set(BLA_VENDOR Apple)
    find_package(BLAS QUIET)
    if(BLAS_FOUND)
        # as a link flag: the framework's path as a library would add -F, a C option, to the Fortran compiles
        target_link_libraries(mlxf_test_exec PRIVATE "-framework Accelerate")
        target_compile_definitions(mlxf_test_exec PRIVATE MLXF_HAVE_BLAS)
    endif()
endif()
install(TARGETS mlxf_test_exec RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

set(MLXF_TEST_RUNS_DIR "${PROJECT_BINARY_DIR}/test_runs")

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
# unit_ops (above 0.5 s in Release): its reduction sub-suite runs every form of every reduction and scan on 16
#   seeded fixtures per seed, the whole-array forms one fixture at a time, on both devices; most of the time is
#   the GPU's small evaluations and the first compilation of each of its kernels.
# compile isolates callback tracing, checked callback failures and shapeless reuse on both devices.
# Cold CPU/GPU JIT compilation can put it above 0.5 s; cached invocations are much shorter.
# transforms (a new area the parity plan names): gradients, vector-Jacobian and Jacobian-vector products and custom
#   rules against closed-form derivatives, on both devices; exported and imported functions; the compilation
#   controls. A process of its own: it switches compilation off and on for the whole process and writes files
#   (and deletes them) in its working directory. Above 0.5 s in Release beside the other entries (0.4 s alone): its
#   leak check runs every transform 300 times on each device.
# fast (a new area the parity plan names): custom Metal kernels, which MLX compiles from source text at their
#   first evaluation; on the GPU they are checked exactly, on the CPU device their refusal is. A process of its
#   own keeps a kernel that fails to compile, which the suite provokes on purpose, apart from the other areas.
#   Alone it takes 0.1 s in Release; beside the gate's other entries, which share the GPU, 0.6 s. Its sub-suite
#   fast_layers checks the fused layers (normalisations, rotary embeddings, attention, cross entropy) against
#   real64 loops on both devices.
# random (a new area the parity plan names): keys and samplers, each judged by the mean and the variance of 2^20
#   values against its distribution's, on both devices and three seeds; a process of its own keeps MLX's global
#   key, which the suite seeds, apart from the other areas. Above 0.5 s in Release (0.7 s alone): the moments are
#   computed on the host in real64 from some 80 samples of 2^20 values.
# io (a new area the parity plan names): arrays written to .npy, safetensors and GGUF files and read back, the
#   .npy files also as bytes; a process of its own, since it writes files (and deletes them) in its working
#   directory.
# distributed (a new area the parity plan names): the group of one process the gate gets, its collectives and its
#   refusals; a process of its own, since MLX's backends are initialised once per process. Its sub-suite
#   distributed_ring, for two processes on MLX's ring backend, runs by name only.
# kernels: test-only models of SIMPLE's pipelines (the polar table's scoring
#   workspace and its shift maps, the polar reprojection) on seeded or analytic fixtures against double-precision
#   oracles, on both
#   devices; its own process keeps the workspace's lifecycle checks (live count and active memory back to warm
#   values) apart from other areas. Above 0.5 s in Release: the oracles' direct sums over every rotation and
#   cell, and the GPU's first compilation of its kernels.
set(MLXF_TEST_AREAS core array ops linalg fft compile transforms fast random io distributed kernels)
foreach(_area IN LISTS MLXF_TEST_AREAS)
    mlxf_add_test(unit_${_area} fast 600 COMMAND $<TARGET_FILE:mlxf_test_exec> test=unit_${_area})
endforeach()

# ---- guard groups: stops that are the contract, each member in a child (expect_aborts) ----------------
# object_contracts: an operation on an empty array, a stale handle used, a call inside an OpenMP region, a
#   float64 operation built on the GPU, and the one-thread guard on the paths that touch no operand (an empty
#   evaluation list, mlx_live_count, mlx_last_error) and on a live private copy released in a region; a
#   invalid 1D/2D FFT normalizations; a Metal kernel built from a spec without outputs and an empty kernel
#   applied; segments of the wrong shape; a factorisation of a rank-1 array, a triangle that is neither 'L' nor
#   'U' and a convolution spec with a list of the wrong length; a strided view reaching past its input; matmul of
#   two integer arrays; a categorical draw given num_samples and shape together and a normal draw whose array mean
#   does not broadcast to its shape; a gradient with respect to position 0 and a compile mode outside its
#   vocabulary; a causal attention given a mask, a rotary
#   embedding given one offset for two batches, a normalisation given an empty weight, the fused attention
#   kernel demanded on the CPU device, a message sent to rank 0 and mlx_from of an array of unknown size; a separate
#   entry because every member ends its process.
mlxf_add_test(object_contracts fast 600 COMMAND $<TARGET_FILE:mlxf_test_exec> expect_aborts object_contracts)

# ---- the budget ----------------------------------------------------------------------------------
set(MLXF_CTEST_BUDGET 13)
get_property(_mlxf_tests DIRECTORY PROPERTY TESTS)
list(LENGTH _mlxf_tests _mlxf_ntests)
if(NOT _mlxf_ntests EQUAL MLXF_CTEST_BUDGET)
    message(FATAL_ERROR "${_mlxf_ntests} CTest entries do not match the budget of ${MLXF_CTEST_BUDGET} "
        "(test/CMakeLists.txt): add checks to an existing area suite, or justify the new process and raise the "
        "budget with the owner's or the plan's decision")
endif()
