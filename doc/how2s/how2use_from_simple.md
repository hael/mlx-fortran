# Use the installed library from Fortran

Build with GNU Fortran 14 or newer and CMake 3.25 or newer, with shared mlx-c available as described in
[the setup guide](how2set_up_dev.md). The installed module records its producing compiler ID and full
version; the consumer must use that same compiler version. Rebuild the library when changing compilers.

Install into a separate prefix, then link the exported target:

```bash
cmake -S . -B build_consumer_release -DCMAKE_BUILD_TYPE=Release -DFORTLS=OFF
cmake --build build_consumer_release --parallel 2
bash scripts/run_fast_gate.sh build_consumer_release
cmake --install build_consumer_release --prefix "$HOME/local/mlxf" --component mlxf
cmake -S test/consumer -B /tmp/mlxf_consumer \
  -DCMAKE_Fortran_COMPILER="$(command -v gfortran)" \
  -Dmlxf_DIR="$HOME/local/mlxf/lib/cmake/mlxf"
cmake --build /tmp/mlxf_consumer --parallel 2
MLX_ENABLE_TF32=0 /tmp/mlxf_consumer/mlxf_consumer
```

Run the checks from a GPU-visible Terminal session. The explicit install check
`bash scripts/check_install.sh build_consumer_release` installs into a disposable prefix containing
spaces, builds and runs the consumer outside the repository, rejects incompatible compiler metadata,
checks that internal modules cannot be imported, and checks pkg-config linking. It requires `pkg-config`.
Set `MLXF_INSTALL_CHECK_KEEP=1` to retain its temporary directory and diagnostics.

In an application whose project has enabled Fortran:

```cmake
find_package(mlxf CONFIG REQUIRED)
target_link_libraries(my_application PRIVATE mlxf::mlxf)
```

`mlxf::mlxf` supplies the installed module directory and discovers shared mlx-c and, when used by the
producer, OpenMP. Set `MLXC_ROOT` to the compatible dependency prefix if it is outside CMake's search
paths. Keep the MLX/mlx-c shared libraries installed at runtime. CMake supplies the consumer build's
runtime search path; an application that installs its own executable should also preserve dependency
search paths, for example with `CMAKE_INSTALL_RPATH_USE_LINK_PATH=ON`.

Import only `mlxf` with an explicit `only:` list. The installation contains the static Fortran library,
`mlxf.mod`, CMake package files and pkg-config metadata. Internal, generated and test modules are private.
Project warning, debug and trap flags remain local to the library build.

For a build system using pkg-config, add `<prefix>/lib/pkgconfig` to `PKG_CONFIG_PATH` and use
`pkg-config --cflags --libs --static mlxf`. The `--static` flag supplies the Fortran archive's shared
mlx-c and optional OpenMP dependencies; mlx-c itself remains dynamically linked. The variables
`fortran_compiler_id` and `fortran_compiler_version` record module compatibility. That build system must
check them against its compiler before compiling; the CMake package performs the check automatically.

The consumer exercises array transfer, `exp(-matmul(a,b))`, checked copy-out and explicit handle release
on CPU and GPU. Follow the [binding contract](../policies/binding_contract_policy.md) for ownership,
supported expressions and the one-submitting-thread rule.

SIMPLE production integration needs its own reviewed performance verdict and integration plan. A future
integration should keep reference tiles and their lifecycle with the calculator, and link this installed
target from the existing SIMPLE build. This guide establishes the generic package interface.
