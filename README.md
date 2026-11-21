# mlx-fortran

A modern Fortran interface to [MLX](https://github.com/ml-explore/mlx), Apple's array framework for the
unified CPU/GPU memory of Apple silicon, built on MLX's C API
[mlx-c](https://github.com/ml-explore/mlx-c).

**Status: scaffold.** The build, the test gate and a toolchain probe are in place; the library is
designed in [`doc/implementation_notes/planned/mlxf_design.md`](doc/implementation_notes/planned/mlxf_design.md).

## What it is for

MLX builds lazy graphs of array operations and runs them on the CPU or the GPU of an Apple-silicon Mac
without copying data between the two. mlx-fortran gives Fortran programs that model in Fortran's own
terms: column-major arrays, 1-based dimensions and indices, `matmul`, `sum` and `exp` that work on
device arrays, and handles whose lifetime the compiler manages. It is developed first for
[SIMPLE](https://github.com/hael/SIMPLE), the cryo-EM package, and its first kernels are SIMPLE's, but
it has no dependence on SIMPLE.

A sketch of the intended use (the API is designed in the plan, not built yet):

```fortran
use mlxf, only: mlx_array, mlx_from, mlx_to_alloc, matmul, exp
type(mlx_array) :: a, b, c
real, allocatable :: x(:,:), y(:,:), z(:,:)
! ... fill x(m,k) and y(k,n)
a = mlx_from(x)              ! an MLX array holding a copy of the Fortran (m,k) array
b = mlx_from(y)
c = exp(-matmul(a, b))       ! a lazy graph, run on the GPU
call mlx_to_alloc(z, c)      ! evaluates, allocates z(m,n) and copies
```

## Building

Requirements: macOS on Apple silicon, CMake 3.25+, GFortran 14+ (`brew install gcc cmake`), and mlx-c as a
shared library, either `brew install mlx-c` (no Xcode needed) or the pinned source build
`scripts/build_mlx_deps.sh` (MLX v0.32.4 and mlx-c v0.8.0 from local clones; needs Xcode's Metal toolchain).

```bash
./compile_clean.sh                       # Release build, fast test gate, install into build/
build/bin/mlxf_test_exec test=unit_core  # the toolchain probe
```

[`doc/how2s/how2set_up_dev.md`](doc/how2s/how2set_up_dev.md) has the details.

## Layout

| path | what |
| --- | --- |
| `src/core/` | the Fortran layer (`mlxf_*` modules) and its testers |
| `src/test/` | test infrastructure, built only with tests |
| `test/` | `mlxf_test_exec`, the one test executable |
| `scripts/` | the gate's checks, the compile helpers, the dependency build |
| `doc/` | the design plan, policies, how-tos |

## License

MIT, as MLX and mlx-c. See [`LICENSE`](LICENSE).
