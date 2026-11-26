# test/offstate/CMakeLists.txt
#
# The off-state build of the toys, a project of its own: the host files of the toy classes and their glue
# submodules (scripts/toy_seam.txt names both), compiled without USE_MLX, so that the glue is its stubs, with
# mlxf_test_defs, the fixture of the polar host route and the program mlxf_offstate_exec. The flags are the library's (cmake/CompilerConfig.cmake); no
# path leads to the library's modules and nothing links it, so a host file that imports an MLX name does not
# compile here. scripts/check_toy_offstate.sh configures, builds and runs it in Debug and Release; the library's
# build does not include it and it registers no CTest entry.
cmake_minimum_required(VERSION 3.25 FATAL_ERROR)

get_filename_component(MLXF_OFFSTATE_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
list(APPEND CMAKE_MODULE_PATH "${MLXF_OFFSTATE_ROOT}/cmake")
include(AutoDetectGCC)

project(mlxf_offstate
    DESCRIPTION "The toys of mlx-fortran built without MLX"
    LANGUAGES Fortran C)

option(MLXF_WERROR      "Treat compiler warnings as errors" ON)
option(MLXF_DEBUG_TRAPS "Debug build: trap invalid, zero and overflow; initialise reals to signalling NaN" OFF)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()
include(CompilerConfig)

# the host route's fill runs its blocks on an OpenMP team, as SIMPLE's does
find_package(OpenMP COMPONENTS Fortran QUIET)
if(NOT OpenMP_Fortran_FOUND)
    message(FATAL_ERROR "The off-state build needs OpenMP for Fortran (GNU Fortran's libgomp); none was found for "
        "${CMAKE_Fortran_COMPILER}.")
endif()

# every file the seam ledger classes as host or glue
set(_ledger "${MLXF_OFFSTATE_ROOT}/scripts/toy_seam.txt")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_ledger}")
file(STRINGS "${_ledger}" _lines REGEX "^mlxf_toy_[a-z0-9_]+ +(host|glue)$")
# a toy's file sits in src/test/toys/ or in the folder of its toy below it
file(GLOB_RECURSE _toy_files "${MLXF_OFFSTATE_ROOT}/src/test/toys/mlxf_toy_*.f90")
set(_sources "")
foreach(_line IN LISTS _lines)
    string(REGEX REPLACE " .*$" "" _stem "${_line}")
    set(_found "")
    foreach(_file IN LISTS _toy_files)
        get_filename_component(_name "${_file}" NAME)
        if(_name STREQUAL "${_stem}.f90")
            list(APPEND _found "${_file}")
        endif()
    endforeach()
    list(LENGTH _found _nfound)
    if(NOT _nfound EQUAL 1)
        message(FATAL_ERROR "${_ledger} names ${_stem}: ${_nfound} files ${_stem}.f90 under src/test/toys, not one.")
    endif()
    list(APPEND _sources "${_found}")
endforeach()
if(NOT _sources)
    message(FATAL_ERROR "No host or glue file in ${_ledger}.")
endif()

# with them the test definitions and the fixture of the polar host route, plain Fortran both
add_executable(mlxf_offstate_exec "${CMAKE_CURRENT_LIST_DIR}/mlxf_offstate_exec.f90" ${_sources}
    "${MLXF_OFFSTATE_ROOT}/src/test/framework/mlxf_test_defs.f90" "${MLXF_OFFSTATE_ROOT}/src/test/toys/polar/mlxf_polarft_host_fixture.f90")
set_target_properties(mlxf_offstate_exec PROPERTIES
    LINKER_LANGUAGE          Fortran
    Fortran_MODULE_DIRECTORY "${PROJECT_BINARY_DIR}/modules")
target_link_libraries(mlxf_offstate_exec PRIVATE mlxf_build_flags OpenMP::OpenMP_Fortran)
list(LENGTH _sources _nsources)
message(STATUS "mlxf_offstate: ${_nsources} host and glue files, ${CMAKE_Fortran_COMPILER_ID} "
    "${CMAKE_Fortran_COMPILER_VERSION}, ${CMAKE_BUILD_TYPE}, no USE_MLX, no library")
