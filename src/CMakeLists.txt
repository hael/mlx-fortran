# src/CMakeLists.txt
#
# The one library target, mlxf. Sources are globbed; CONFIGURE_DEPENDS reruns cmake when a file under
# src/ is added or removed. Test-only sources (src/test/ and every *_tester.f90) are never part of the
# library: test/CMakeLists.txt compiles them into mlxf_test_exec, so that the installed library holds no
# test, kernel or benchmark code and a test-only dependency (FFTW for a benchmark) never reaches it.

file(GLOB_RECURSE MLXF_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.[Ff]90")
file(GLOB_RECURSE MLXF_TEST_ONLY_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/test/*.[Ff]90"
    "${CMAKE_CURRENT_SOURCE_DIR}/*_tester.[Ff]90")
if(MLXF_TEST_ONLY_SOURCES)
    list(REMOVE_ITEM MLXF_SOURCES ${MLXF_TEST_ONLY_SOURCES})
endif()
set(MLXF_TEST_ONLY_SOURCES "${MLXF_TEST_ONLY_SOURCES}" PARENT_SCOPE)

mlxf_add_library(mlxf ${MLXF_SOURCES})
set_target_properties(mlxf PROPERTIES VERSION ${PROJECT_VERSION})
target_include_directories(mlxf
    PUBLIC  $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/mlxf>
    PRIVATE "${MLXF_GEN_DIR}")
target_link_libraries(mlxf PUBLIC mlxc)
if(USE_OPENMP)
    target_link_libraries(mlxf PUBLIC OpenMP::OpenMP_Fortran)
endif()

install(TARGETS mlxf
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(DIRECTORY "${PROJECT_BINARY_DIR}/modules/mlxf/"
    DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/mlxf"
    FILES_MATCHING PATTERN "*.mod" PATTERN "*.smod")
