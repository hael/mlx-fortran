# cmake/Dependencies.cmake
#
# mlx-c (the C API of MLX), OpenMP and the Python of the build scripts.
# ------------------------------------------------------------------------------
# mlx-c: an installed package with its CMake config (share/cmake/MLXC). Searched, in order, under
# MLXC_ROOT (cache or environment), the tree scripts/build_mlx_deps.sh installs (.deps/install) and the
# default prefixes (Homebrew's when its bin/ is on PATH: brew install mlx-c).
# ------------------------------------------------------------------------------
find_package(MLXC CONFIG REQUIRED
    HINTS "${CMAKE_SOURCE_DIR}/.deps/install")
if(NOT TARGET mlxc)
    message(FATAL_ERROR "The MLXC package config defines no mlxc target (${MLXC_DIR})")
endif()
# A static libmlxc links mlx privately and its exported config does not find mlx, so a consumer cannot
# link it; the shared library carries its own dependencies (mlx, libc++, Metal).
get_target_property(_mlxc_type mlxc TYPE)
if(NOT _mlxc_type STREQUAL "SHARED_LIBRARY")
    message(FATAL_ERROR "mlx-c at ${MLXC_DIR} is a ${_mlxc_type}; mlx-fortran needs the shared library "
        "(build it with -DBUILD_SHARED_LIBS=ON, as scripts/build_mlx_deps.sh and Homebrew do)")
endif()
get_target_property(MLXF_MLXC_LIBRARY mlxc LOCATION)
if(NOT MLXC_VERSION VERSION_EQUAL MLXF_MLXC_PINNED_VERSION)
    message(WARNING "mlx-c ${MLXC_VERSION} found; mlx-fortran is written against ${MLXF_MLXC_PINNED_VERSION}. "
        "The generated layer follows the headers found, the hand-written layer may not.")
endif()
# libmlxc and libmlx are named @rpath/... when built from source; CMAKE_INSTALL_RPATH_USE_LINK_PATH adds
# only directories outside the project, and .deps/install is inside it, so installed executables get the
# mlx-c library directory explicitly (dyld searches the executable's rpaths for libmlx too).
list(APPEND CMAKE_INSTALL_RPATH "${MLX_C_LIBRARY_DIRS}")

# ------------------------------------------------------------------------------
# OpenMP: only so that the library can refuse calls from inside a parallel region (the !$ lines)
# ------------------------------------------------------------------------------
if(USE_OPENMP)
    find_package(OpenMP REQUIRED COMPONENTS Fortran)
endif()

# ------------------------------------------------------------------------------
# The interpreter of the build's scripts and of the fast gate (scripts/run_fast_gate.sh reads MLXF_PYTHON3),
# not the python3 on PATH; the floor is the newest Python those scripts need (SIMPLE's floor).
# ------------------------------------------------------------------------------
find_package(Python3 3.7 REQUIRED COMPONENTS Interpreter)
set(MLXF_PYTHON3 "${Python3_EXECUTABLE}" CACHE INTERNAL "Python of the build scripts and the fast gate")
