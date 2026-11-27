# src/CMakeLists.txt
#
# The one library target, mlxf. Sources are globbed; CONFIGURE_DEPENDS reruns cmake when a file under
# src/ is added or removed. Test-only sources (src/test/ and every *_tester.f90) are never part of the
# library: test/CMakeLists.txt compiles them into mlxf_test_exec, so that the installed library holds no
# test, kernel or benchmark code and a test-only dependency (FFTW for a benchmark) never reaches it.

# The C helpers of src/core (the lstat of mlxf_libc) are library sources too; src/test's C, the ABI probe, is
# compiled by test/CMakeLists.txt.
file(GLOB_RECURSE MLXF_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.[Ff]90"
    "${CMAKE_CURRENT_SOURCE_DIR}/core/*.c")
file(GLOB_RECURSE MLXF_TEST_ONLY_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/test/*.[Ff]90"
    "${CMAKE_CURRENT_SOURCE_DIR}/*_tester.[Ff]90")
if(MLXF_TEST_ONLY_SOURCES)
    list(REMOVE_ITEM MLXF_SOURCES ${MLXF_TEST_ONLY_SOURCES})
endif()
set(MLXF_TEST_ONLY_SOURCES "${MLXF_TEST_ONLY_SOURCES}" PARENT_SCOPE)

# The generated bind(c) layer (scripts/gen_mlxc_bindings.py): one types module and one interface module per
# header of the mlx-c being linked, and mlxf_c_signatures, the C signature classes of scripts/mlxc_signatures.txt,
# written into build/gen at build time and rerun when a header, either script or the ledger changes. The build
# fails unless the generated and skipped names equal the independent prototype list
# (scripts/list_mlxc_prototypes.py). The set of files is known at configure time (--list-outputs).
set(_mlxc_include "${MLX_C_INCLUDE_DIRS}")
file(GLOB MLXF_MLXC_HEADERS CONFIGURE_DEPENDS "${_mlxc_include}/mlx/c/*.h")
set(_gen_script  "${PROJECT_SOURCE_DIR}/scripts/gen_mlxc_bindings.py")
set(_list_script "${PROJECT_SOURCE_DIR}/scripts/list_mlxc_prototypes.py")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_gen_script}")
execute_process(
    COMMAND "${MLXF_PYTHON3}" -I "${_gen_script}" "${_mlxc_include}" "${MLXF_GEN_DIR}" --list-outputs
    OUTPUT_VARIABLE _gen_outputs
    RESULT_VARIABLE _gen_rc
    OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _gen_rc EQUAL 0 OR NOT _gen_outputs)
    message(FATAL_ERROR "scripts/gen_mlxc_bindings.py --list-outputs failed on ${_mlxc_include}")
endif()
string(REPLACE "\n" ";" MLXF_GENERATED_SOURCES "${_gen_outputs}")
add_custom_command(
    OUTPUT ${MLXF_GENERATED_SOURCES} "${MLXF_GEN_DIR}/mlxc_coverage.txt" "${MLXF_GEN_DIR}/mlxc_prototypes.txt"
    COMMAND "${MLXF_PYTHON3}" -I "${_list_script}" "${_mlxc_include}" -o "${MLXF_GEN_DIR}/mlxc_prototypes.txt"
    COMMAND "${MLXF_PYTHON3}" -I "${_gen_script}" "${_mlxc_include}" "${MLXF_GEN_DIR}"
            --expect "${MLXF_GEN_DIR}/mlxc_prototypes.txt"
    DEPENDS ${MLXF_MLXC_HEADERS} "${_gen_script}" "${_list_script}" "${PROJECT_SOURCE_DIR}/scripts/mlxc_signatures.txt"
    COMMENT "Generating the bind(c) layer from the mlx-c headers (mlxf_c_*) and the signature classes"
    VERBATIM)

mlxf_add_library(mlxf ${MLXF_SOURCES} ${MLXF_GENERATED_SOURCES})
set_target_properties(mlxf PROPERTIES VERSION ${PROJECT_VERSION})
# A target that links mlxf sees mlxf.mod alone, in the build tree as in the installed package: after each build
# it is copied into include/mlxf, the build interface, while every other module stays in the library's own module
# directory (a parent project that embeds the library could otherwise import mlxf_c_array and reach a handle).
# The test executable, the library's own, adds that directory itself.
set(MLXF_PUBLIC_MODULE_DIR "${PROJECT_BINARY_DIR}/include/mlxf")
file(MAKE_DIRECTORY "${MLXF_PUBLIC_MODULE_DIR}")
set_property(TARGET mlxf PROPERTY INTERFACE_INCLUDE_DIRECTORIES
    "$<BUILD_INTERFACE:${MLXF_PUBLIC_MODULE_DIR}>" "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/mlxf>")
target_include_directories(mlxf PRIVATE "${PROJECT_BINARY_DIR}/modules/mlxf" "${MLXF_GEN_DIR}")
add_custom_command(TARGET mlxf POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${PROJECT_BINARY_DIR}/modules/mlxf/mlxf.mod"
            "${MLXF_PUBLIC_MODULE_DIR}/mlxf.mod"
    VERBATIM)
target_link_libraries(mlxf PUBLIC mlxc)
if(USE_OPENMP)
    target_link_libraries(mlxf PUBLIC OpenMP::OpenMP_Fortran)
endif()

install(TARGETS mlxf EXPORT mlxfTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR} COMPONENT mlxf
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR} COMPONENT mlxf)
# Only the user module is installed. Every other module file (the generated mlxc_* layer, the registry, the
# internal helpers) would let a consumer reach a handle and free it behind the reference count; gfortran
# writes into mlxf.mod everything a consumer of its public names needs.
install(FILES "${PROJECT_BINARY_DIR}/modules/mlxf/mlxf.mod" DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/mlxf" COMPONENT mlxf)
