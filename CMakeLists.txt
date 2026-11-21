cmake_minimum_required(VERSION 3.25 FATAL_ERROR)

# Helper modules first; pick a GNU toolchain before project() unless the user set compilers.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(AutoDetectGCC)

# ------------------------------------------------------------------------------
# Project
# ------------------------------------------------------------------------------
project(mlx_fortran
    VERSION 0.1.0
    DESCRIPTION "A modern Fortran interface to the MLX array framework"
    HOMEPAGE_URL "https://github.com/hael/mlx-fortran"
    LANGUAGES Fortran C)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ------------------------------------------------------------------------------
# Build options
# ------------------------------------------------------------------------------
option(BUILD_TESTS       "Build mlxf_test_exec and the *_tester modules" ON)
option(USE_OPENMP        "Compile with OpenMP so that calls from inside a parallel region are refused" ON)
option(FORTLS            "Install the fortls Fortran language server and its Claude Code plugin in the build tree" ON)
option(MLXF_WERROR       "Treat compiler warnings as errors (CI)" OFF)
option(MLXF_DEBUG_TRAPS  "Debug build: trap invalid, zero and overflow; initialise reals to signalling NaN" OFF)
# On a development Mac the device tests must run: a session that cannot open a GPU fails them instead of
# skipping (the CI's virtual runners set it OFF).
if(APPLE AND CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
    set(_mlxf_require_gpu_default ON)
else()
    set(_mlxf_require_gpu_default OFF)
endif()
option(MLXF_REQUIRE_GPU  "Fail the device tests when no GPU can be opened (a compile definition of mlxf_test_exec)"
    ${_mlxf_require_gpu_default})
# The mlx-c release the hand-written layer is written against; another one configures with a warning.
set(MLXF_MLXC_PINNED_VERSION 0.8.0)

# ------------------------------------------------------------------------------
# Install layout and default build type
# ------------------------------------------------------------------------------
include(GNUInstallDirs)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}" CACHE PATH "Installation prefix" FORCE)
endif()
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS Debug Release RelWithDebInfo MinSizeRel)
endif()

# ------------------------------------------------------------------------------
# Generated-source directory (each target owns its module directory: mlxf_add_library)
# ------------------------------------------------------------------------------
set(MLXF_GEN_DIR "${PROJECT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${MLXF_GEN_DIR}")

# ------------------------------------------------------------------------------
# Compiler configuration and dependencies (mlx-c, OpenMP, Python for the scripts)
# ------------------------------------------------------------------------------
include(CompilerConfig)
include(Dependencies)

# Build facts the library reports at run time (mlxf_version)
configure_file(
    "${CMAKE_SOURCE_DIR}/cmake/mlxf_build_info.inc.in"
    "${MLXF_GEN_DIR}/mlxf_build_info.inc"
    @ONLY)

# ------------------------------------------------------------------------------
# Subdirectories. Testing is enabled before test/ so that its add_test calls register.
# ------------------------------------------------------------------------------
if(BUILD_TESTS)
    enable_testing()
endif()
add_subdirectory(src)      # the library target mlxf
if(BUILD_TESTS)
    add_subdirectory(test) # mlxf_test_exec (with the testers) and the CTest entries
endif()
add_subdirectory(scripts)  # fortls for Claude Code

# ------------------------------------------------------------------------------
# Testing
# ------------------------------------------------------------------------------
if(BUILD_TESTS)
    # `make check` is the fast gate by hand: the same gate every compile_*.sh runs between build and
    # install unless given --exclude-tests (scripts/run_fast_gate.sh).
    add_custom_target(check
        COMMAND "${CMAKE_SOURCE_DIR}/scripts/run_fast_gate.sh" "${CMAKE_BINARY_DIR}"
        USES_TERMINAL)
endif()

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
message(STATUS "========================================")
message(STATUS "mlx-fortran configuration summary")
message(STATUS "========================================")
message(STATUS "Version:              ${PROJECT_VERSION}")
message(STATUS "Build type:           ${CMAKE_BUILD_TYPE}")
message(STATUS "Install prefix:       ${CMAKE_INSTALL_PREFIX}")
message(STATUS "Fortran compiler:     ${CMAKE_Fortran_COMPILER} (${CMAKE_Fortran_COMPILER_ID} ${CMAKE_Fortran_COMPILER_VERSION})")
message(STATUS "C compiler:           ${CMAKE_C_COMPILER} (${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION})")
message(STATUS "----------------------------------------")
message(STATUS "mlx-c:                ${MLXC_VERSION} (${MLXF_MLXC_LIBRARY})")
message(STATUS "mlx-c headers:        ${MLX_C_INCLUDE_DIRS}")
message(STATUS "OpenMP:               ${USE_OPENMP}")
message(STATUS "Build tests:          ${BUILD_TESTS}")
message(STATUS "Require a GPU:        ${MLXF_REQUIRE_GPU}")
message(STATUS "Warnings as errors:   ${MLXF_WERROR}")
message(STATUS "========================================")
