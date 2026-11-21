# scripts/CMakeLists.txt
#
# The Fortran language server for Claude Code: fortls in a virtual environment of the build tree, its
# configuration and a one-plugin marketplace (fortls-lsp@mlxf-build) written here with this tree's paths,
# and the plugin registered for the checkout by cmake/InstallFortls.cmake (target fortls). Offline it
# only warns. Lifted from SIMPLE.
if(FORTLS)
  set(FORTLS_VENV        "${CMAKE_BINARY_DIR}/tools/fortls")
  set(FORTLS_MARKETPLACE "${CMAKE_BINARY_DIR}/claude-plugins")
  set(FORTLS_PLUGIN      "${FORTLS_MARKETPLACE}/fortls-lsp")
  file(WRITE "${CMAKE_BINARY_DIR}/fortls.json" "{
  \"source_dirs\": [\"${CMAKE_SOURCE_DIR}/src/**\", \"${CMAKE_SOURCE_DIR}/test\", \"${MLXF_GEN_DIR}\"],
  \"excl_paths\": [\"${CMAKE_BINARY_DIR}/**/CMakeFiles/**\"],
  \"include_dirs\": [\"${MLXF_GEN_DIR}\"],
  \"pp_suffixes\": [\".f90\"],
  \"incl_suffixes\": [\".inc\"],
  \"pp_defs\": {},
  \"lowercase_intrinsics\": true,
  \"hover_signature\": true,
  \"use_signature_help\": true,
  \"disable_autoupdate\": true,
  \"nthreads\": 4
}
")
  file(WRITE "${FORTLS_MARKETPLACE}/.claude-plugin/marketplace.json" "{
  \"name\": \"mlxf-build\",
  \"owner\": { \"name\": \"mlx-fortran\" },
  \"plugins\": [ { \"name\": \"fortls-lsp\", \"source\": \"./fortls-lsp\",
                 \"description\": \"Fortran code intelligence for mlx-fortran through fortls\" } ]
}
")
  file(WRITE "${FORTLS_PLUGIN}/.claude-plugin/plugin.json" "{
  \"name\": \"fortls-lsp\",
  \"version\": \"1.0.0\",
  \"description\": \"Fortran code intelligence for mlx-fortran through fortls: diagnostics after edits, definitions and references by symbol\"
}
")
  file(WRITE "${FORTLS_PLUGIN}/.lsp.json" "{
  \"fortls\": {
    \"command\": \"${FORTLS_VENV}/bin/fortls\",
    \"args\": [\"--config\", \"${CMAKE_BINARY_DIR}/fortls.json\", \"--disable_autoupdate\"],
    \"extensionToLanguage\": { \".f90\": \"fortran\", \".F90\": \"fortran\", \".inc\": \"fortran\" }
  }
}
")
  add_custom_target(fortls ALL
    COMMAND "${CMAKE_COMMAND}" -DPYTHON=${Python3_EXECUTABLE} -DVENV=${FORTLS_VENV}
            -DMARKETPLACE=${FORTLS_MARKETPLACE} -DSOURCE_DIR=${CMAKE_SOURCE_DIR}
            -P "${CMAKE_SOURCE_DIR}/cmake/InstallFortls.cmake"
    COMMENT "Fortran language server (fortls) for Claude Code"
    VERBATIM)
endif()
