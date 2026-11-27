cmake_minimum_required(VERSION 3.25 FATAL_ERROR)

# Helper modules first; pick a GNU toolchain before project() unless the user set compilers.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")
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
# MLXF_REQUIRE_GPU is declared after the dependencies, whose CUDA build of MLX makes it default ON
# The mlx-c release the hand-written layer is written against; another one configures with a warning.
set(MLXF_MLXC_PINNED_VERSION 0.8.0)

# ------------------------------------------------------------------------------
# Install layout and default build type
# ------------------------------------------------------------------------------
include(GNUInstallDirs)
# Paths are the library's own (PROJECT_*), never CMAKE_SOURCE_DIR or CMAKE_BINARY_DIR, so that a parent project
# can add_subdirectory() it (rule cmakeroot); the defaults below are set only when it is the top-level project.
if(PROJECT_IS_TOP_LEVEL AND CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "${PROJECT_BINARY_DIR}" CACHE PATH "Installation prefix" FORCE)
endif()
if(PROJECT_IS_TOP_LEVEL AND NOT CMAKE_BUILD_TYPE)
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
# On a development Mac, and with a CUDA build of MLX, the device tests must run: a session that cannot open a GPU
# fails them instead of skipping (the CI's virtual runners set it OFF).
if((APPLE AND CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64") OR MLXF_MLX_CUDA)
    set(_mlxf_require_gpu_default ON)
else()
    set(_mlxf_require_gpu_default OFF)
endif()
option(MLXF_REQUIRE_GPU  "Fail the device tests when no GPU can be opened (a compile definition of mlxf_test_exec)"
    ${_mlxf_require_gpu_default})

# Build facts the library reports at run time (mlxf_version)
configure_file(
    "${PROJECT_SOURCE_DIR}/cmake/mlxf_build_info.inc.in"
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

# Installed consumers need only mlxf.mod, the archive and these dependency/compiler facts.
include(CMakePackageConfigHelpers)
set(MLXF_CMAKE_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/cmake/mlxf")
configure_package_config_file(cmake/mlxfConfig.cmake.in
    "${PROJECT_BINARY_DIR}/mlxfConfig.cmake"
    INSTALL_DESTINATION "${MLXF_CMAKE_INSTALL_DIR}")
write_basic_package_version_file("${PROJECT_BINARY_DIR}/mlxfConfigVersion.cmake"
    VERSION "${PROJECT_VERSION}" COMPATIBILITY SameMajorVersion)
install(EXPORT mlxfTargets NAMESPACE mlxf:: DESTINATION "${MLXF_CMAKE_INSTALL_DIR}" COMPONENT mlxf)
install(FILES "${PROJECT_BINARY_DIR}/mlxfConfig.cmake" "${PROJECT_BINARY_DIR}/mlxfConfigVersion.cmake"
    DESTINATION "${MLXF_CMAKE_INSTALL_DIR}" COMPONENT mlxf)
set(MLXF_PC_OPENMP "")
if(USE_OPENMP)
    set(MLXF_PC_OPENMP "${OpenMP_Fortran_FLAGS}")
endif()
configure_file(cmake/mlxf.pc.in "${PROJECT_BINARY_DIR}/mlxf.pc" @ONLY)
install(FILES "${PROJECT_BINARY_DIR}/mlxf.pc" DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig" COMPONENT mlxf)
# the lifetime checker consumers run on their own sources, with the analysis module the repository's rules share
install(PROGRAMS scripts/check_consumer.py DESTINATION "${CMAKE_INSTALL_DATADIR}/mlxf" COMPONENT mlxf)
install(FILES scripts/mlxf_consumer_checks.py DESTINATION "${CMAKE_INSTALL_DATADIR}/mlxf" COMPONENT mlxf)

# ------------------------------------------------------------------------------
# Testing
# ------------------------------------------------------------------------------
if(BUILD_TESTS)
    # `make check` is the fast gate by hand: the same gate every compile_*.sh runs between build and
    # install unless given --exclude-tests (scripts/run_fast_gate.sh).
    add_custom_target(check
        COMMAND "${PROJECT_SOURCE_DIR}/scripts/run_fast_gate.sh" "${PROJECT_BINARY_DIR}"
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
