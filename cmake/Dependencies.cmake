# cmake/Dependencies.cmake
#
# mlx-c (the C API of MLX), OpenMP and the Python of the build scripts.
# ------------------------------------------------------------------------------
# mlx-c: an installed package with its CMake config (share/cmake/MLXC). Searched, in order, under
# MLXC_ROOT (cache or environment), the tree scripts/build_mlx_deps.sh installs (.deps/install) and the
# default prefixes (Homebrew's when its bin/ is on PATH: brew install mlx-c).
# ------------------------------------------------------------------------------
# mlx-c's MLXCConfig.cmake (0.8.0) calls find_package_handle_standard_args(MLX_C ...) inside the package MLXC,
# which makes CMake print a developer warning on every configure. FPHSA_NAME_MISMATCHED acknowledges that one
# mismatch; it is set only around this call, so a mismatch in any other package still warns. Our checks below
# read the target and MLXC_VERSION, never MLX_C_FOUND.
# Not REQUIRED: a miss is answered with what was searched and the three ways to provide mlx-c (SIMPLE's and
# XEMA's policy: a missing dependency fails loudly and says how to install it), not CMake's list of file names.
set(FPHSA_NAME_MISMATCHED TRUE)
find_package(MLXC CONFIG QUIET
    HINTS "${CMAKE_SOURCE_DIR}/.deps/install")
unset(FPHSA_NAME_MISMATCHED)
# A config that was found but rejected itself (a dependency of it missing) leaves MLXC_DIR set: its own
# reason is the useful message there, not the search.
if(NOT MLXC_FOUND AND MLXC_DIR)
    message(FATAL_ERROR
        "mlx-c's package config at ${MLXC_DIR} was found but did not load:\n"
        "  ${MLXC_NOT_FOUND_MESSAGE}\n"
        "Reinstall that mlx-c (brew reinstall mlx-c, or scripts/build_mlx_deps.sh), or point MLXC_ROOT at another.")
endif()
if(NOT MLXC_FOUND)
    if(MLXC_ROOT)
        set(_mlxf_root "MLXC_ROOT=${MLXC_ROOT}: no share/cmake/MLXC under it")
    elseif(DEFINED ENV{MLXC_ROOT})
        set(_mlxf_root "MLXC_ROOT=$ENV{MLXC_ROOT} (environment): no share/cmake/MLXC under it")
    else()
        set(_mlxf_root "MLXC_ROOT: not set")
    endif()
    if(EXISTS "${CMAKE_SOURCE_DIR}/.deps/install")
        set(_mlxf_deps "${CMAKE_SOURCE_DIR}/.deps/install: present, but holds no mlx-c")
    else()
        set(_mlxf_deps "${CMAKE_SOURCE_DIR}/.deps/install: absent (scripts/build_mlx_deps.sh not run)")
    endif()
    find_program(_mlxf_brew brew)
    if(_mlxf_brew)
        get_filename_component(_mlxf_brew_prefix "${_mlxf_brew}" DIRECTORY)
        get_filename_component(_mlxf_brew_prefix "${_mlxf_brew_prefix}" DIRECTORY)
        set(_mlxf_brew_line "Homebrew (${_mlxf_brew_prefix}): mlx-c not installed")
    else()
        set(_mlxf_brew_line "Homebrew: no brew on PATH")
    endif()
    message(FATAL_ERROR
        "================================================================================\n"
        "  mlx-fortran needs mlx-c (the C API of MLX) as a shared library, and none was found.\n"
        "  Searched:\n"
        "    ${_mlxf_root}\n"
        "    ${_mlxf_deps}\n"
        "    ${_mlxf_brew_line}\n"
        "  Provide it one way, then reconfigure (./compile_clean.sh, or rm -rf build && cmake -S . -B build):\n"
        "    Homebrew, no Xcode needed:   brew install mlx-c\n"
        "    the pinned source build:     scripts/build_mlx_deps.sh   (mlx-c ${MLXF_MLXC_PINNED_VERSION}; clones of\n"
        "                                 ml-explore/mlx and mlx-c, Xcode's Metal toolchain and the network)\n"
        "    an install elsewhere:        MLXC_ROOT=<prefix holding share/cmake/MLXC> ./compile_clean.sh\n"
        "================================================================================\n")
endif()
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
    find_package(OpenMP COMPONENTS Fortran)
    if(NOT OpenMP_Fortran_FOUND)
        message(FATAL_ERROR
            "${CMAKE_Fortran_COMPILER} cannot build an OpenMP program.\n"
            "  macOS: brew reinstall gcc (Homebrew's GCC ships libgomp)\n"
            "  The compiler's own error is in CMakeFiles/CMakeConfigureLog.yaml of the build directory.\n"
            "  Without OpenMP (calls from inside a parallel region are then not refused): -DUSE_OPENMP=OFF")
    endif()
endif()

# ------------------------------------------------------------------------------
# The interpreter of the build's scripts and of the fast gate (scripts/run_fast_gate.sh reads MLXF_PYTHON3),
# not the python3 on PATH; the floor is the newest Python those scripts need (SIMPLE's floor).
# ------------------------------------------------------------------------------
find_package(Python3 3.7 COMPONENTS Interpreter)
if(NOT Python3_Interpreter_FOUND)
    message(FATAL_ERROR
        "No Python 3.7 or newer found; the build generates its C layer and runs its gate with it.\n"
        "  macOS: xcode-select --install, or brew install python\n"
        "  A specific one: cmake -S . -B build -DPython3_EXECUTABLE=/path/to/python3")
endif()
set(MLXF_PYTHON3 "${Python3_EXECUTABLE}" CACHE INTERNAL "Python of the build scripts and the fast gate")
