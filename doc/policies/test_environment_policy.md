# Test Environment Policy

What a test is in mlx-fortran, where it goes and what runs when. A short version of SIMPLE's test policy
with XEMA's test-admission rules (`doc/architecture_principles.md`, section 7) and the rules a library on two
devices adds. The rules in short, for writing a test, are in
`.github/skills/mlxf-modern-fortran/references/testing.md`.

## 1. The environment

One test executable, `mlxf_test_exec`, built by every compile script unless it is given `--exclude-tests`
(CMake option `BUILD_TESTS`, default ON). It compiles the test-only sources (`src/test/` and every
`*_tester.f90`); the library `mlxf` never contains them. Every test is reached through
`mlxf_test_exec test=<name> [suite=<sub-suite>]`; `test=list` lists what exists.

The test-only tree, `src/test/`, has four folders, each with its `.inf`: `framework/` (the assertions and the
summary, the suite registry, the test definitions, the NaN-safe reductions, the ABI probe of the generated layer),
`toys/` (the opaque device state and the seam tester, and one folder per toy: `polar/`, `projector/`, `recon/`),
`oracles/` (the independent double-precision references the toys and benchmarks are judged against) and `bench/`
(the benchmarks). Module names do not carry the folder; a library module's tester stays beside it under
`src/core/`. No Fortran or C file sits at the top of `src/test/`.

| label | entries | when | what |
| --- | --- | --- | --- |
| `fast` | one `unit_<area>` per area, and the guard groups | every compile script, between build and install | unit tests: hermetic, in-process (guard groups: one child per member), one thread, seconds |
| none | `bench_<x>` | by hand | benchmarks: measure-only modes, and accuracy modes that hold frozen gates too large for the fast gate; never registered with CTest |

**The fast gate is part of the build.** `scripts/run_fast_gate.sh` runs between `make` and
`make install`: first the static gate `scripts/check_tree.sh` (`check_descr.py`, `check_rules.py`,
`check_test_registry.py`, `check_guide_imports.py`, `check_submodule_linkage.py`, `format_use_blocks.py
--check`, a warning for untracked sources), then `ctest -L fast` with half the cores, then
`ctest_budget.py`, which fails the build on a failed entry and only warns when the gate takes more than
60 s of real time. A failed gate installs nothing. Each fast entry has a 600 s CTest deadline and runs with
`OMP_NUM_THREADS=1`, `OMP_WAIT_POLICY=PASSIVE`, `OMP_THREAD_LIMIT=4` and `MLX_ENABLE_TF32=0`.

**Checks are free, processes are budgeted.** A CTest entry is an isolation unit, not an assertion.
`MLXF_CTEST_BUDGET` in `test/CMakeLists.txt` must equal the registered count or configuration fails; it
changes only with an owner decision or a plan that names the new entry, recorded in `doc/history/`.

`unit_core`'s sub-suite `abi` is the ABI probe of the generated layer: the interfaces of `src/test/framework/mlxf_abi_probe.h`
are generated with the library's mapping table (`scripts/gen_mlxc_bindings.py --probe`, into `build/gen_test/`) and
its echo functions are compiled by Apple's clang (`xcrun clang`, the compiler of mlx-c; CMake's C compiler is GCC)
into an object of `mlxf_test_exec`; elsewhere than macOS by the build's C compiler, which reads mlx-c's headers as
system headers (GCC reports an unused static of `mlx/c/array.h`). Each of the 35 classes of argument and result
is echoed at least once; `int`,
`bool`, `float`, `double` and the three optional pairs both in a register and on the stack; the size, alignment,
field offsets and field sizes of the 36 structs and the values of the 23 enumerators are compared with C's by name.
It calls no MLX function and runs in every session. A struct or enumerator that mlx-c adds fails it until the C
tables of `src/test/framework/mlxf_abi_probe.c` list it.

The current process budget is **13**, the most the parity plan's decision 21 allows: areas `core`, `array`, `ops`,
`linalg`, `fft`, `compile`, `transforms`, `fast`, `random`, `io`, `distributed`, `kernels`, plus the `object_contracts`
guard group (thirty members, including invalid FFT normalizations, dtypes
outside `MLX_DTYPES`, a Metal kernel spec without outputs, an empty kernel applied, segments of the wrong shape, a
factorisation of a rank-1 array, an unknown triangle, a convolution spec with a list of the wrong length, a strided
view reaching past its input, `matmul` of two integer arrays, a categorical draw given `num_samples` and `shape`
together, a normal draw whose array mean does not broadcast to its shape, a gradient with respect to position 0, a
compile mode outside `MLX_COMPILE_MODES`, a causal attention given a mask, a rotary embedding given one offset for two
batches, a normalisation given an empty weight, the fused attention kernel demanded on the CPU device and a message sent to
rank 0). Error reductions in test code go through
`nan_maxval` (`src/test/framework/mlxf_test_reduce.f90`, rule `nanmax`), which turns any NaN into +infinity. The `fast` area (the parity
plan's decision 21) runs custom Metal kernels on the GPU against exact Fortran references and checks their
refusal on the CPU device; it provokes a Metal compilation failure on purpose, which is why it has a process of
its own. Its sub-suite `fast_layers` checks `mlx_layer_norm`, `mlx_rms_norm`, `mlx_rope`,
`mlx_scaled_dot_product_attention` and `mlx_cross_entropy` against real64 loops over Fortran subscripts within
`FAST_TOLERANCES` (calibrated on seed 1 on both devices, frozen, then seeds 2 and 3), on both devices. The `random` area (the parity plan's decision 21) judges every sampler by the mean and the variance of 2^20
values against its distribution's, within `RANDOM_SIGMAS` standard errors, on both devices and on keys of three seeds,
and checks keys, shapes, dtypes, categories and permutations exactly; it seeds MLX's global key, which is why it has a
process of its own. The `io` area (decision 21) writes every transfer kind at ranks 0 to 4 to `.npy` files, reads
each file as bytes (the NumPy header parsed in Fortran: the kind, the shape reversed, the data equal to the host
array's bytes), reads it back as an array and writes it again byte for byte; it checks safetensors and GGUF round
trips with names and metadata, the refusals through `status`, `nbytes`, `itemsize` and `mlx_buffer_size`, and the
text of a graph; it writes files in its working directory and deletes them, which is why it has a process of its
own. The `distributed` area (decision 21) checks the group of one process the gate gets: its size and one-based
rank, the five collectives returning their operand, and the refusals of messages, of a split and of a strict start
through `status`; MLX initialises its backends once per process, hence a process of its own. `unit_distributed
suite=distributed_ring` is named-only: two processes started on MLX's ring backend (the parity plan's Progress has
the command and the host file); the gate never runs it. `unit_core`'s sub-suite `stream` checks streams (a stream
of one's own as a device's default, waiting for it), device availability, the memory and wired limits and the
refusal of a Metal capture. The `transforms` area (decision 21) checks `mlx_value_and_grad`, `mlx_vjp` and `mlx_jvp` on a
polynomial, `exp(a x)` and a chain of two matrix products against closed-form derivatives within `GRAD_TOLERANCES`
(calibrated on seed 1 on both devices, frozen, then seeds 2 and 3), and exactly: positions among the inputs, custom
rules, a checkpoint, `mlx_stop_gradient`, `mlx_depends`, the gradient function's lifecycle and its failures through
`status`; its sub-suite `export` writes functions to files in its working directory, reads them back and deletes
them, and switches compilation off and on, which is why the area has a process of its own. The compile suite also
checks empty local handles in a two-thread OpenMP region; no live MLX work is submitted there. The operation areas compare both devices with independent Fortran
references; `array` also runs 10,000 evaluated iterations per new operation family and checks exact
active memory, live handles and stale releases. The compile area checks byte identity for exactly
representable compiled/uncompiled arithmetic on each device, shapeless trace reuse and callback error
recovery; the array area also runs 10,000 compiled calls and verifies complete closure teardown.
The kernels area holds test-only models of SIMPLE's pipelines written against `mlxf` as a user writes
(`src/test/toys/`; the toy example policy rules the form of new ones and of their refactoring); its sub-suite `polar_table` checks the polar table's scoring workspace
on a seeded fixture against a double-precision ring oracle, on both devices, with row bounds calibrated
on the CPU device and frozen in `src/test/framework/mlxf_test_defs.f90` before the first GPU run; the draw on the
device's own rows, refusals of mismatched blocks, schedule identity and the workspace's lifecycle. Its
sub-suite `polar_shiftmap` checks the workspace's shift maps on analytic fixtures against a direct
double-precision residual at every cell, with caps confirmed on the CPU device and frozen there before the
first GPU run: the maps, the mode where its margin is clear, the zero radius, the folding of orders beyond the
directions, the Nyquist ring, the width and the log evidence against the host's moments, candidate order and
tiles, refusals and rebuilds, and 100 prepare-score-invalidate cycles. The shift-map suite also checks
requested-output profiling, changed weights/grid/band, strict width cutoffs and exact teardown, an exact tie (the
mode the first cell in SIMPLE's order), and each pair's width and log evidence against the host oracle on three
keyed-noise seeds. Its sub-suite `oracle_polar` asserts the self-checks of the polar score's and the shift map's
host oracles within their own limits (host only).
Its sub-suite `polarft_tail` checks the fused tail of the dense score (a custom Metal kernel, the form `metal`):
the refusal on the CPU device, identity and repeatability, small tile plans against the compiled tail within
frozen bounds, and the kernel objects' lifecycle; `polarft_calc` and `eul_prob_tab` run their GPU checks with
both forms. Its sub-suite `oracle_projection` asserts the self-checks of the projection's host oracles (the
direct transforms' 12, the projection's 32). Its sub-suite `projector` checks the toy projector's polar gather
(the graph form on both devices, the fused Metal kernel on the GPU) on the oracle's phantom, a seeded cube and the
edge and boundary queries against the double-precision projection oracle, within `PROJ_FIXTURE_ERR` (calibrated on
seed 1 on both devices, frozen, then seeds 2 and 3), with its controls (a constant spectrum, the identity against
the oracle's own polar coordinates, a plane wave's pattern, Hermitian pairs), repeatability, 100 lifecycle cycles
and the fused form's refusals. Its sub-suite `projector_chain` takes two projected volumes through family A on both
routes (host and device) and both forms to the dense rows, against an oracle chain within `PROJ_CHAIN_ERR_HOST`
and `PROJ_CHAIN_ERR_DEVICE`, with the refusals of the device route and three runs bit for bit.
Its sub-suite `pcg_solver` checks the toy PCG engine (`mlxf_toy_pcg_solver_mlx`, its record in `mlxf_toy_pcg_solver`) on both devices: every stop, count
and reason on small diagonal systems whose iterates are known in rationals (`rtol`, `xtol` and their order, the step
test's epsilon, `maxits`, fixed iterations, indefinite products at iterations 1 and 2, the refusals, a used and a
rejected start, the recomputation's 24, 26, 31 and 52 applications), and the stencil problem of
`mlxf_oracle_pcg` through a test-only operator against its explicit matrix and Cholesky. Its sub-suite
`reconstructor_pcg` checks the toy `reconstructor_pcg` on the full-coverage fixture (n = 8, `mlxf_oracle_recon_fixture`)
against `mlxf_oracle_recon_pcg` on both devices, within `RECON_PCG_TOLERANCES` (calibrated on seed 1 on both
devices, frozen, then seeds 2 and 3): the mask, window, envelopes, kernel and preconditioner spectra, ridge and
right-hand side; the operator and the preconditioner against their explicit matrices; the iterates of SIMPLE's
production (2 and 5 iterations, absolute ridge) and of the engine's rules up to their stop; start and ship; three
assemblies bit for bit; 100 lifecycle cycles; each of the operator's five procedures on host volumes against its
device form brought to the host, byte for byte, and its refusal on the host backend. Rule T (200 iterations past the
engine's rules) is reported, not gated.
`unit_kernels suite=reconstructor_pcg_n32` is named-only: the same at n = 32 against the oracle's matrix-free
products (the iterates at 1, 2 and 5 and the stop iteration and test judged, the stop iterate reported).
`unit_kernels suite=polar_shiftmap_accuracy` is named-only: a direct-residual sample at the production
window/screen geometry, on both devices. It uses the same frozen caps, has assertions, and is outside the
fast CTest process budget.
Its sub-suite `seam` checks the shape the toys share (toy example policy, section 8), on both devices: the opaque
device state's lifecycle on a test double (a scalar and an array `class(device_work)` component, a wrong dynamic
type refused), and of the calculator, the projector and the reconstructor 1,000 cycles of `new` and `kill` that
leave the live handles and the active memory as they were, the host backend making no device object, and what the
host backend cannot do refused with its message. Its sub-suite `polarft_host` checks the polar calculator's host
route (`l_mlx` false): the distances and the drawn rotations against `mlxf_oracle_polar` at the MLX backend's
tolerances, the same bytes from a team of 1 and of 4 threads, the fill's two branches within those tolerances on
seeds 1, 2 and 3, and the refusals; it writes the table as lines `polarft_host ...` in hexadecimal.
`scripts/check_toy_offstate.sh` builds `test/offstate/` (the toys' host files and glue stubs without `USE_MLX`
and without the library) in Debug and Release, runs its program and, with `--exec`, holds its table to the lines
of `unit_kernels suite=polarft_host` byte for byte; the release gate runs it, and it is not a CTest entry.
Constants several test modules share live in `src/test/framework/mlxf_test_defs.f90`, a defs module (rule `defs`).
Its sub-suite `eul_prob_tab_neigh` checks the reference lists on the polar host route's fixture: the calculator's
list route (any list, the dense route for every reference in order) against the memo oracle within bounds
calibrated on the CPU device (`POLAR_NEIGH_*`), against the dense route bit for bit on the host and the CPU device
and within the tail's tolerance on the GPU; the driver `eul_prob_tab_neigh` (cones, the two-stage state fill, both
block orders, the covers route, dense and pairs) against the oracle of the lists `mlxf_oracle_neigh` (sub-suite
`oracle_neigh`, its self-checks), exactly for the lists, pools and occupancy; repeatability over repeats, slots,
teams and invocations; and the pair-list kernel's frozen tolerance on the GPU and its refusal elsewhere.

**Benchmarks** are `mlxf_test_exec test=bench_<x> suite=<mode> [key=value ...]`, listed in the registry's
`BENCHES` table and reached through `run_bench` (`check_test_registry.py` holds the two to each other). They
run by hand, never in CTest, and append rows to `./bench_<x>*.tsv` in the working directory. A mode that
measures asserts nothing. A mode that judges, such as `bench_polar_table suite=accuracy` (the polar table's
64,000-pair block against its DFT-matrix oracle, at SIMPLE's sizes), uses the assertions of `mlxf_test_utils`
and fails the process like a test. Its bounds are calibrated on the CPU device and frozen in
`src/test/framework/mlxf_test_defs.f90` before its first GPU run. `bench_polar_table suite=shiftmap` measures the shift
maps on SIMPLE's grid (read from a key = value file of SIMPLE's rows) with SIMPLE's column names.
`bench_projector` times the reprojection of one state at SIMPLE's bench (`suite=time`: the canonical driver to the
evaluated banks; `suite=chain`: on to the reference bins on `route=host|device` and a dense score) and judges 16
directions against the oracle on the device's own transform (`suite=accuracy`, `PROJ_BENCH_ERR`); unlike the polar
bench, a key a suite does not read stops it. `bench_recon_pcg` runs the toy `reconstructor_pcg` at SIMPLE's boxes (n = 160 and 256, the padded 320³ and 512³):
`suite=transform` the padded transforms alone; `suite=time` the canonical driver (new, the support, `set_raw_accum`,
`end_accum`, the solve, kill) per `system=P|R` and `rules=F2,F5,E,R4`, with `out=` for the maps' bytes and the
histories in hexadecimal for comparing two invocations; `suite=profile` the stages and pieces; `suite=probe` the
transforms' share, the cost of a wait, the inner products' forms and the drift; `suite=accuracy` the device against
the oracle at bench size (it asserts). A key a suite does not read stops it.
`bench_insert_probe suite=probe` measures an atomic gridding insertion
against the gridding oracle (the protected-update probe of the roadmap's decision 14). `bench_blas
suite=crossover [nmax=]` times `sgemm` and `cgemm` through the system's CBLAS (Accelerate, linked to the test
executable on macOS only) against `matmul` on MLX's CPU and GPU devices, with and without the transfer from and
to Fortran arrays, and prints the first size at which MLX wins (`doc/how2s/how2replace_blas.md`). `scripts/run_parts.sh`
starts any of them (`RUN_PARTS_BENCH`, `RUN_PARTS_SUITE`, `RUN_PARTS_UNIT`).
`tail=graph` or `tail=metal` selects the tail's form in `accuracy`, `time` and `profile`; `suite=time` reads
`passes=` (default 3) and writes the passes and their median; `scripts/run_parts.sh` sums its parts' median
rates. Timed runs
follow the plan's rules: Release, an idle machine with the load recorded, best of 3 after a warm-up, two
invocations, and the precision mode in every row. `suite=shiftmap` refuses `nthr=`: the maps run on the
device with one submitting thread. A key a suite does not read stops the benchmark (exit status 2), as in the
other benchmarks. `suite=neigh` times the neighbourhood fill of one part (`lists=route|dense|pairs`: the list
route, the dense fill with selection, the pair-list kernel; comma lists of `bt rt mode cone order orient`;
`seed=`), appending the list's columns (listed and computed pairs, occupancy, blocks, the pools, the host step)
to the 30 that `scripts/run_parts.sh` reads; `check=1` holds the list route on the accuracy block to its frozen
bounds (`POLAR_NEIGH_BLOCK_*`). `suite=maps` times one map's maps (`maps=window|screen`, one `ptiles=`) of one part
(`nparts=`, `part=`, `go=`) with `passes=` timed passes and writes one row of `bench_polar_table.tsv` in the time
suite's column order, so that `scripts/run_parts.sh` (`RUN_PARTS_SUITE=maps RUN_PARTS_UNIT=maps`) times the maps at
one or more processes; `nthr=` sizes the host team only. `widths=quarter|none` selects synthetic
cutoff survivors; `widths=all evidence=0` is the matched baseline. Cutoff/evidence rows do not claim an
all-width CPU speedup. Grid files must carry fresh `simple_commit`, `fftw_plans` and full-team rates before
ratios are used; `revision=` identifies the measured mlx-fortran tree. Performance runs are currently deferred
by the owner; running either accuracy suite is correctness validation, not a throughput benchmark.

`bench_kernel_forms` sets ways of writing a Metal kernel beside the toys' current kernels, on the GPU only (a
session without one is refused). The current kernels enter through the toys' own spec functions (`tail_spec`,
`gather_spec`, `probe_spec`), so the bench holds no copy of a current source; the alternatives' sources and specs
are in `mlxf_bench_kernel_forms_src.f90`. `suite=probe [form=a|b|c|d]` asserts what threadgroup memory and the
SIMD-group functions give through the wrapper. `suite=tail|reduce|sizes|select|insert|waits` take `mode=agree`,
which asserts each alternative against the current form before anything is timed (bit for bit where the order of
the arithmetic is the same, else within `FORMS_REDUCE_TOL` or `FORMS_INSERT_TOL`, frozen in
`mlxf_test_defs.f90` on seed 1), and `mode=time`, which runs an A-A control and five interleaved pairs of medians
of five and prints decision 3's verdict of the kernel-forms plan; `suite=tail mode=part` is one process of
`scripts/run_parts.sh` (`RUN_PARTS_BENCH=bench_kernel_forms RUN_PARTS_SUITE=tail`) and `suite=sizes mode=compile`
the first evaluations of new sizes in a fresh process. A key a suite does not read stops it.

## 2. What a test is

- It can fail, and its failure reaches the exit status (`mlxf_test_utils` assertions; `mlxf_test_exec`
  exits 1 when one failed).
- Its expected value comes from outside the code under test: a closed form, a brute force in plain
  Fortran (double precision where it matters), an exact array operation, or numbers from an emulation
  pasted with a note on how they were made.
- Its tolerances are named and derived from the arithmetic, or measured on the CPU device and frozen
  before the test is used as a gate. A tolerance widened until a test passed is a finding.
- It asserts conventions: memory order, index base, dimension numbering, FFT sign and normalisation.
- Storage identity is compared with `bits_equal` (transfer-based), never `==` on reals.
- An error is reduced with `nan_maxval` or `nan_max` (`src/test/framework/mlxf_test_reduce.f90`, rule `nanmax`), never
  `maxval(abs(...))` or `x = max(x, abs(...))`, which may skip a NaN; a history is finite before it is compared.
- Two samples of the active memory are compared only after `mlx_synchronize()`: the device releases a buffer
  when the work that used it completes, so a sample taken while the stream is busy counts buffers in flight.
- Its random draws come from fixed seeds.
- Four kinds, never mixed: identity (bytes equal), correctness (against an independent value),
  robustness (a distribution over seeds), performance (timings, never pass/fail).
- A test that comes with a fix is shown to fail on the tree before the fix.

## 3. Failure paths

- A stop that is the library's contract (a stale handle used, an operation on an empty array, a call from
  inside an OpenMP region) is tested by a member of a guard group, run by
  `mlxf_test_exec expect_aborts <group>` in its own child process and accepted only when it exits with
  `MLXF_HARD_ERROR_STATUS`; the parent reports every faulty member. Never a raw `WILL_FAIL`: it accepts
  any non-zero exit, a broken fixture or a runtime check included. One guard group is one CTest entry.
- The intended stop is the last statement the child can reach, and its fixture is proven by a passing
  sibling. Errors a checked procedure reports through `status` are tested in-process.
- A member is a row of the `GUARDS` table and a `case` of `run_guard` in `src/test/framework/mlxf_test_registry.f90`;
  the child is `mlxf_test_exec guard=<member>`, and `mlxf_test_exec expect_abort <member>` runs one member as
  the group does. The group `object_contracts` holds the stops of the binding contract (an operation on an
  empty array, a stale handle used, a call inside an OpenMP region, a float64 operation built on the GPU, and
  the one-thread guard on the paths that touch no operand: an empty evaluation list, `mlx_live_count`,
  `mlx_last_error`, a live private copy released in a region).
  Without a GPU the members are not run (each would stop for that reason instead of its own): a skip, or a
  failure under `MLXF_REQUIRE_GPU`.
- No test pins a compiler defect: a compiler that fixes one must not fail the build. A test that meets a
  defect accepts the conforming result as well (the allocatable handle component: a counted copy or the
  diagnosed bitwise one) and tests the diagnosis through a bypass every compiler takes (`allocate(source=)`).

## 4. Devices

- MLX runs an operation on the CPU device or the GPU device (Metal or CUDA). A test of an operation runs on
  every device present; `mlxf_test_exec device=cpu|gpu|all` (default `all`) restricts it. A tester takes
  its devices from `test_devices(devs)` of `mlxf_test_utils`.
- The sessions, one classification (`mlxf_test_utils`: `test_devices`, `gpu_present`, `cpu_only_mlx`,
  `gpu_check_runs`, `metal_check_runs`; the guard gate of `mlxf_test_exec` and the outside programs of
  `test/consumer/` follow it). The GPU backend is what `mlx_metal_is_available()` and `mlx_cuda_is_available()`
  report (at most one is true):

  | GPU backend | GPU count | session | tests | under `MLXF_REQUIRE_GPU` |
  | --- | --- | --- | --- | --- |
  | Metal | > 0 | Metal with a device | the devices `device=` asks for | as they are |
  | Metal | 0 | Metal without a device (headless, sandboxed, virtual) | skip: `SKIP: no GPU device in this session; a Metal build of MLX cannot allocate` | failure |
  | CUDA | > 0 | CUDA with a GPU (`scripts/build_mlx_deps.sh --cuda`; the count is `cudaGetDeviceCount`'s, `CUDA_VISIBLE_DEVICES` applies) | the devices `device=` asks for; a check of Metal's own behaviour skips with `SKIP: Metal-only check on a CUDA build` | as they are |
  | CUDA | 0 | CUDA without a GPU (none present, or none visible through `CUDA_VISIBLE_DEVICES`) | skip: `SKIP: no GPU device in this session; a CUDA build of MLX cannot allocate` | failure |
  | none | 0 | CPU-only MLX (`scripts/build_mlx_deps.sh --cpu-only`; on Linux every build but `--cuda`) | the CPU device; a check that needs the GPU or Metal's allocator skips with `SKIP: GPU-only check on a CPU-only MLX build` | failure |

  A GPU is present when `mlx_device_count(MLX_DEVICES%gpu) > 0`; the two backend queries say only what was
  compiled in. A Metal or CUDA build of MLX without a GPU cannot allocate arrays on either device (CUDA's
  allocator needs a GPU at its construction), the memory limits included; a CPU-only MLX allocates on the heap.
  Without NVIDIA's driver library a CUDA build does not load at all (its `libmlx.so` needs `libcuda.so.1`): a
  build host such as dell2 links through the toolkit's stub (`MLXF_CUDA_STUB_DIR`) and runs nothing. Nothing of
  the CUDA sessions has run yet; they run at work (the CUDA plan's Part C). A test asserts no more
  about an absent device than that the call returns: MLX 0.32 accepts an absent GPU as the default device and
  fails only at the first allocation. Test code asks for the GPU only through `mlxf_test_utils` (rule
  `devquery`; the device tester, which tests the count itself, is its ledger). Each `GUARDS` member names the
  device its fixture needs (`cpu` or `gpu`); on a CPU-only MLX the `gpu` members skip with the same message. The
  GPU-only checks of the fast gate on a CPU-only MLX, five: in `unit_core` the GPU's device information, the
  recovery gate (the maximum buffer is the Metal allocator's), the memory and wired limits (Metal's allocator) and
  a Metal capture, and `guard_float64_on_gpu`; the Metal kernels' GPU tests run only on the GPU anyway. The
  Metal-only checks (`metal_check_runs`) are the recovery gate, the memory and wired limits, the Metal capture,
  the failed evaluation beyond the maximum buffer of `unit_io`, the device tester's `max_buffer_length` and
  `memory_size` keys (a CUDA GPU checks its `total_memory`, `free_memory` and `sm_XY` architecture instead), and
  the kernel wrapper's threadgroup above the device's limit (CUDA clips the block to the grid): with
  a GPU they run on Metal and skip by name on CUDA, without one they skip as the GPU-only checks do, and a
  session's counts stay those of its backend. The
  headless gate is reproduced on a Mac with `sandbox-exec -p "(version 1)(allow default)(deny iokit-open)"` around a
  build configured with `-DMLXF_REQUIRE_GPU=OFF`; the CPU-only gate with `scripts/ci_cpu_job.sh`, and on Linux with
  `scripts/ci_linux_job.sh` (the same job, then the embedding and off-state checks).
- CMake option `MLXF_REQUIRE_GPU` (default ON on macOS arm64 and with a CUDA build of MLX, whose `libmlx.so`
  links NVIDIA's `libcuda.so.1`; OFF in the CI), a compile definition of the test executable, turns those skips
  into failures, so a development Mac or a CUDA machine can never pass the gate without running the device tests.
- GPU results are compared with tolerances, never bytes: the GPU computes in float32 and complex64 only,
  and atomic reductions sum in an order that changes from run to run. Identity tests (bytes) are for
  pure data movement; float64 is tested on the CPU device only.

## 5. Where a test goes

- In the area of the code it tests, as a sub-suite (a `run_suite` row of
  `src/test/framework/mlxf_test_registry.f90`). A new area is a row in `AREAS`, a `case` branch, an entry of
  `MLXF_TEST_AREAS` in `test/CMakeLists.txt` and a budget raise, kept in step by
  `scripts/check_test_registry.py`.
- Fast tier only if it is hermetic (no network, no user file, no dependence on core count, load or
  clock), runs in-process on one thread, and leaves no files behind. An entry above 0.5 s in Release says
  why in its registration comment. A test that is too slow for the fast label is shrunk or optimized (a
  smaller fixture, fewer iterations, a cheaper form of the same check), as long as it can still fail on the
  guarantee it names.
- **Named-only sub-suites** (owner ruling, 2026-11-22): where a gate is shrunk, a full form whose cost grows
  with the machine (the recovery gate's half-batch evaluation allocates half the GPU's maximum buffer) may be
  kept as a sub-suite listed in the registry's `NAMED_ONLY` table. Its area runs it only when `suite=` names
  it, and `test=list` lists it. The fast gate keeps a form that tests the same guarantee at a fixed cost. A
  plan names the points where the named-only form runs (a new machine, a phase exit);
  `check_test_registry.py` holds every `NAMED_ONLY` name to a `run_suite` row. Today: `unit_core
  suite=recovery_half`. `unit_fast suite=kernel_sources` is named-only for another reason: every kernel of the
  wrapper's tests carries a CUDA source, and a spec without its backend's source is refused through `status`;
  with `records=<dir>` it writes one record per kernel application for `scripts/check_cuda_sources.sh`, which
  wraps each CUDA source as MLX does and compiles it with NVRTC for `sm_100a` and `sm_120a` on a machine without a
  GPU (compiled, not run). Its checks stay out of the fast gate so that the gate's counts are those of the base.
- Both build types: a change to tests is verified in Debug and Release.

## 6. Testers

- `mlxf_<thing>_tester.f90` beside the module it tests: a `private` module exporting only
  `run_all_<thing>_tests`, which prints `**** running all <thing> tests ****`; each `test_<what>` prints
  its name first. A tester that owns a named-only sub-suite (section 5) also exports that sub-suite's
  `run_all_<name>_tests`. No `stop` or `error stop` in a tester outside a guard-group member.
- A tester that needs private entities is a submodule of the module it tests; no entity is public only
  for a tester. A submodule calls no private procedure whose body is in its module: no plain one (gfortran
  before 16 does not link it) and no separate module procedure either (gfortran 15 on Linux does not link that);
  a separate module procedure the module and its submodule share has its body in the submodule
  (`scripts/check_submodule_linkage.py`).
- Deleting a test needs a kept test that reaches the same branch with the same assertion.

## 7. Python

Python the build or the gate runs uses the standard library and nothing newer than 3.7, the floor of
`find_package(Python3 3.7 ...)` in `cmake/Dependencies.cmake`. Passing on macOS does not show a breach.
