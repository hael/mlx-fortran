# Use the installed library from Fortran

Build with GNU Fortran 14 or newer and CMake 3.25 or newer, with shared mlx-c available as described in
[the setup guide](how2set_up_dev.md). The installed package records its producing compiler ID and full
version and the mlx-c version it was built with: a consumer must use that same compiler version and find
exactly that mlx-c release (the installed interfaces were generated from its headers), or `find_package(mlxf)`
refuses with "mlxf Fortran compiler mismatch" or "mlxf mlx-c mismatch". Rebuild the library when changing
either. `mlxf.pc` carries the same facts (`fortran_compiler_version`, `mlxc_version`). Every configure of the
library below passes `-DFORTLS=OFF`, so that the build writes nothing into the source tree or the editor settings.

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
spaces, builds and runs the consumer outside the repository, rejects a package config naming another compiler
version or another mlx-c version, checks that internal modules cannot be imported, and checks pkg-config
linking. It requires `pkg-config`. `--require-gpu` (the release gate's mode) makes a session without a GPU a
failure instead of a skip; `mlxf_consumer require-gpu` does the same for the consumer alone. Set
`MLXF_INSTALL_CHECK_KEEP=1` to retain its temporary directory and diagnostics. `scripts/release_gate.sh` runs
the install check on its Debug and its Release build, from a snapshot of the commit.

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
`fortran_compiler_id`, `fortran_compiler_version` and `mlxc_version` record module and interface
compatibility. That build system must check them against its compiler and its mlx-c before compiling; the
CMake package performs both checks automatically.

Embedding instead of installing: a parent project may `add_subdirectory()` the library; its targets that link
`mlxf` see `mlxf.mod` alone (the build tree's `include/mlxf`), as an installed consumer does
(`scripts/check_embed.sh` builds and runs such a parent program and proves a private import refused).

The consumer exercises array transfer, `exp(-matmul(a,b))`, checked copy-out and explicit handle release
on CPU and GPU. The examples beside it are the documents' programs: `mlxf_example_first.f90` (the README's),
`mlxf_example_differences.f90` (the dtype-and-result table of the [quickstart](../quickstart.md), which also
lists what the caller must do and what the library enforces) and `mlxf_example_errors.f90` (a status, the named
owner of a view, the three device sessions). Follow the [binding contract](../policies/binding_contract_policy.md)
for ownership, supported expressions and the one-submitting-thread rule.

SIMPLE production integration needs its own reviewed performance verdict and integration plan. A future
integration should keep reference tiles and their lifecycle with the calculator, and link this installed
target from the existing SIMPLE build. This guide establishes the generic package interface.

## The shape an integration takes

The toys under `src/test/` model the file layout a SIMPLE class has once it can run on MLX
([toy example policy](../policies/toy_example_policy.md), section 8): host files that import no MLX name, a glue
submodule `<unit>_mlx` beside each host unit that crosses to the device (its body under `#ifdef USE_MLX`, stubs
under `#else`), device modules behind one opaque component, and a backend chosen at `new`. The tables below are
the record an integration reads: what each toy file stands for in SIMPLE (read at `d354efee2`), and what each
mirrored host procedure gained. `scripts/toy_seam.txt` and `scripts/toy_mirror.txt` are the checked lists.

| Toy file (`src/test/`) | Class | Stands for in SIMPLE |
| --- | --- | --- |
| `mlxf_toy_device_work.f90` | host | a new module: the abstract type a class holds its device state as |
| `mlxf_toy_polarft_calc.f90` | host | `src/main/pftc/simple_polarft_calc.f90`, which gains the component `ws(:)`, the member `l_mlx` and the "MLX" interface block |
| `mlxf_toy_polarft_core.f90`, `_memo.f90`, `_block.f90`, `_shiftmap.f90` | host | `simple_polarft_core.f90`, `_memo.f90`, `_block.f90`, `_shiftmap.f90`, each gaining guarded calls |
| `mlxf_toy_polarft_core_mlx.f90`, `_memo_mlx.f90`, `_block_mlx.f90`, `_shiftmap_mlx.f90` | glue | new submodules beside those four |
| `mlxf_toy_polarft_workspace.f90` and its submodules `_lifecycle`, `_score`, `_tail`, `_shiftmap` | device | a new module: the calculator's device state and kernels |
| `mlxf_toy_eul_prob_tab.f90` | host | `src/main/strategies/search/probabilistic/simple_eul_prob_tab.f90`, whose fill gains the MLX branch beside its OpenMP loop |
| `mlxf_toy_projector.f90`, `mlxf_toy_projector_pft_batch.f90` | host | `src/main/image/simple_projector.f90`, `simple_projector_pft_batch.f90` |
| `mlxf_toy_projector_mlx.f90`, `mlxf_toy_projector_pft_batch_mlx.f90` | glue | new submodules beside those two |
| `mlxf_toy_projector_workspace.f90` | device | a new module: the padded transform, the expanded cube, the gather's kernels, the bank handed to the calculator |
| `mlxf_toy_reconstructor_pcg.f90` | host | `src/main/volume/simple_reconstructor_pcg.f90` (with the members of `simple_pcg_lattice.f90` it reads) |
| `mlxf_toy_reconstructor_pcg_mlx.f90` | glue | a new submodule beside it: the device forms of the operator, the adapter, the transfers |
| `mlxf_toy_reconstructor_pcg_workspace.f90` | device | a new module: the spectra, envelopes, mask and right-hand side |
| `mlxf_toy_pcg_solver.f90` | host | `src/main/opt/simple_pcg_solver.f90`, for the record `pcg_solver_outcome` (SIMPLE's host engine is not modelled) |
| `mlxf_toy_pcg_solver_mlx.f90` | device | a new module beside it: `pcg_operator` and `pcg_solve` on device vectors |

What each mirrored host procedure gained. "A guarded call" is `if( self%l_mlx ) call <name>_mlx(self, ...)`; where
the toy has no host route the other branch is a refusal.

| Host procedure | What it gained |
| --- | --- |
| `polarft_calc%new` | the backend from `params%l_mlx`; a guarded call that makes the two workspaces; on the host backend, the per-thread work of the block kernel |
| `polarft_calc%kill` | `kill` on each element of `ws(:)` before the deallocation |
| `vol_pad2ref_pfts_opt` | on the device route a guarded call that passes the projector's bank on as `class(device_work)`; the host route as in SIMPLE |
| `polarft_calc%memoize_refs`, `%memoize_ref_bins` | a guarded call each (the tiles and the memos of the device route); on the host backend SIMPLE's sums per angular bin |
| `polarft_calc%score_block_posterior` | a guarded call on the MLX backend; on the host backend SIMPLE's block kernel (no change of its dummy list) |
| `polarft_calc%new_shiftmap`, `%kill_shiftmap`, `%shiftmap_mode` | a guarded call each; the host backend refuses the maps (not modelled) |
| `eul_prob_tab%fill_tab_range` | one selection: the host branch calls `score_block_posterior` from inside `!$omp parallel do` over the blocks; the MLX branch submits and collects serially from one thread |
| `projector%new` | the backend (an optional `params`); a guarded call that makes the device state; a refusal on the host backend |
| `projector%get_cmat`, `%pad_fft`, `%expand_cmat`, `%is_expanded`, `%kill_expanded` | a guarded call each |
| `projector%kill` | `kill` on `ws` before the deallocation |
| `fproject_polar_batch_opt` | a guarded call that projects on the device and copies the bank to `pfts_refs` |
| `reconstructor_pcg%new` | the backend (an optional `params`); a guarded call that makes the device state and sends the envelopes; a refusal on the host backend |
| `reconstructor_pcg%set_window_sphere` | a guarded call that sends or clears the hard support |
| `reconstructor_pcg%end_accum` | two guarded calls: the right-hand side with a view of the raw density for the host's statistics, and the finalisation's wait; its private steps `update_lambda_from_density`, `finalize_density_accum`, `finalize_khat` and `calibrate_kernel` one each |
| `reconstructor_pcg%mask_mul`, `%apply_normal`, `%apply_normal_kernel`, `%apply_precond`, `%dot_real_volume` | SIMPLE's host arrays kept; a guarded call each, whose glue sends the volume, applies the device form and brings the result back (in an integration these keep their host bodies, and the solve alone crosses) |
| `reconstructor_pcg%solve_accum` | a guarded call: the start sent, the device engine run through the glue's adapter, the solution brought back unless the solve is given up; the window at the start and at the exit stays host code |
| `reconstructor_pcg%kill` | `kill` on `ws` before the deallocation |

The build without MLX is `test/offstate/` (`scripts/check_toy_offstate.sh`): the same host and glue files without
`USE_MLX` and without the library.
