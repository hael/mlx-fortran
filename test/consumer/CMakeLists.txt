cmake_minimum_required(VERSION 3.25)
project(mlxf_consumer LANGUAGES Fortran)
find_package(mlxf CONFIG QUIET)
if(NOT mlxf_FOUND)
    message(FATAL_ERROR "Cannot use installed mlxf: ${mlxf_NOT_FOUND_MESSAGE}. Set mlxf_DIR to <prefix>/lib/cmake/mlxf.")
endif()
# the consumer and the examples the documents show (README.md, doc/quickstart.md), each a program of its own
foreach(_program mlxf_consumer mlxf_example_first mlxf_example_differences mlxf_example_errors mlxf_example_user_safety)
    add_executable(${_program} ${_program}.f90)
    target_link_libraries(${_program} PRIVATE mlxf::mlxf)
    # the installed lifetime checker runs on each program first: a finding fails the build
    mlxf_check_lifetime(${_program})
endforeach()
