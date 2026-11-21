# cmake/CompilerConfig.cmake
#
# Compiler policy and flags. GNU Fortran only, floor 14, failing loudly (SIMPLE's and XEMA's policy). Flags are
# attached to the mlxf_build_flags INTERFACE target, never forced into the cache, so a user or an embedding
# project keeps its own (XEMA's flag policy). doc/architecture_principles.md, section 6, gives the reasons.
# ------------------------------------------------------------------------------
# Compiler checks
# ------------------------------------------------------------------------------
set(MLXF_GFORTRAN_MINIMUM 14.0)
if(NOT CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    message(FATAL_ERROR
        "Unsupported Fortran compiler: ${CMAKE_Fortran_COMPILER_ID} (${CMAKE_Fortran_COMPILER}).\n"
        "mlx-fortran requires GNU Fortran >= ${MLXF_GFORTRAN_MINIMUM}.\n"
        "  macOS: brew install gcc\n"
        "Then reconfigure in a clean build directory: rm -rf build && cmake -S . -B build")
endif()
# Finalization of function results and intent(out) dummies, which the handle lifetime rests on, is
# conformant from GFortran 13; 14 is the floor SIMPLE and XEMA build with.
if(CMAKE_Fortran_COMPILER_VERSION VERSION_LESS MLXF_GFORTRAN_MINIMUM)
    message(FATAL_ERROR
        "gfortran ${CMAKE_Fortran_COMPILER_VERSION} is too old; mlx-fortran requires >= ${MLXF_GFORTRAN_MINIMUM}.\n"
        "Point CMake at a newer one: cmake -S . -B build -DCMAKE_Fortran_COMPILER=/path/to/gfortran-16")
endif()
if(APPLE)
    if(NOT (CMAKE_C_COMPILER_ID MATCHES "Clang|AppleClang" OR CMAKE_C_COMPILER_ID STREQUAL "GNU"))
        message(FATAL_ERROR "C compiler must be GCC or AppleClang on macOS. Found: ${CMAKE_C_COMPILER_ID}")
    endif()
elseif(NOT CMAKE_C_COMPILER_ID STREQUAL "GNU")
    message(FATAL_ERROR "Only GCC is supported for C on Linux. Found: ${CMAKE_C_COMPILER_ID}")
endif()
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# ------------------------------------------------------------------------------
# Fortran flags
# ------------------------------------------------------------------------------
add_library(mlxf_build_flags INTERFACE)
target_compile_options(mlxf_build_flags INTERFACE
    # -cpp: the generated build-information include. -std=f2018: a public library stays standard Fortran
    # (XEMA rejects -std because it disables GNU intrinsics XEMA uses; this library uses none).
    -cpp -ffree-line-length-none -fimplicit-none -std=f2018
    -Wall -Wextra -Wimplicit-interface -Waliasing -Wsurprising -Wline-truncation
    # GCC's maybe-uninitialized analysis gives false positives on hidden descriptor fields of allocatable
    # and derived-type code (SIMPLE); off in every build type.
    -Wno-maybe-uninitialized
    # an overriding type-bound procedure must take a passed object it may not read
    -Wno-unused-dummy-argument
    # the public generics extend intrinsic names (sum, matmul, exp, ...) and lifecycles name kill
    -Wno-intrinsic-shadow
    $<$<BOOL:${MLXF_WERROR}>:-Werror>
    $<$<CONFIG:Release>:-O3>
    $<$<CONFIG:Debug>:-O0;-g;-fbacktrace;-Wuninitialized;-Wunused>
    # On macOS the GFortran 16 debug runtime has crashed under pointer and array-temps checks on
    # C-interoperable pointers (SIMPLE); bounds, do and mem stay on there.
    $<$<AND:$<CONFIG:Debug>,$<PLATFORM_ID:Darwin>>:-fcheck=bounds,do,mem>
    $<$<AND:$<CONFIG:Debug>,$<NOT:$<PLATFORM_ID:Darwin>>>:-fcheck=all>
    # Opt-in: the floating-point environment the Fortran main program sets also governs MLX's C++ CPU
    # kernels in the same process, which may legitimately produce infinities.
    $<$<AND:$<CONFIG:Debug>,$<BOOL:${MLXF_DEBUG_TRAPS}>>:-ffpe-trap=invalid,zero,overflow;-finit-real=snan>
    $<$<CONFIG:RelWithDebInfo>:-O2;-g>)

# mlxf_add_library(<name> <sources...>): a static library whose module files live in its own directory,
# reachable only through its build interface (XEMA's per-library module directories): installing the
# library never installs a module of the test executable, and nothing imports a module it does not link.
function(mlxf_add_library name)
    add_library(${name} STATIC ${ARGN})
    set(_moddir "${PROJECT_BINARY_DIR}/modules/${name}")
    file(MAKE_DIRECTORY "${_moddir}")
    set_target_properties(${name} PROPERTIES
        Fortran_MODULE_DIRECTORY "${_moddir}"
        POSITION_INDEPENDENT_CODE ON)
    target_include_directories(${name} PUBLIC $<BUILD_INTERFACE:${_moddir}>)
    target_link_libraries(${name} PRIVATE mlxf_build_flags)
endfunction()

# Installation rewrites RPATHs with install_name_tool; reserve load-command space for longer paths.
if(APPLE)
    string(APPEND CMAKE_EXE_LINKER_FLAGS " -Wl,-headerpad_max_install_names")
endif()

# ------------------------------------------------------------------------------
# RPATH: installed executables find libmlxc where it was linked from
# ------------------------------------------------------------------------------
if(APPLE)
    set(CMAKE_INSTALL_RPATH "@executable_path/../lib" "${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}")
else()
    set(CMAKE_INSTALL_RPATH "$ORIGIN/../lib" "${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}")
endif()
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
