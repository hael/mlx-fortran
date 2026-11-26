# A newcomer's review: the library as a potential user meets it

Reviewed **2026-11-26** at **`96c5c5c`** plus the working tree's `mlx_rope` GPU bound, on the M2 Ultra
(GNU Fortran 16.2.0, Homebrew MLX 0.32.4 and mlx-c 0.8.0). The library was built and installed as the README
says (`-DBUILD_TESTS=OFF`, into a prefix outside the repository: 10 s, the first example ran), and thirteen small
programs were then written against the installed `mlxf` the way a Fortran programmer new to MLX would write them.
The programs and their driver are in `~/for_claude/mlxf_user_review_2026-11-26/` (`run_probes.sh`; in
`p12` the slice loop is switched off so the callback half runs). No source of the repository was changed.

## What works well

The installed package is clean: one `mlxf.mod` of 55 KB, a consumer file compiles in 0.1 s, `find_package`
works, and the intrinsics keep working on plain arrays beside the generics (`sum`, `count`, `matmul`, `max`,
`maxloc` checked). Shapes, 1-based subscripts (`maxloc(a)` gives `4 3` for a (4, 3) array) and the README's
example behave as documented. The quickstart's differences table is what a newcomer needs most. A compiled
Fortran callback ran on the first attempt. The diagnosed misuses are well diagnosed: a bitwise copy (an
allocatable handle component) stops with a message that lists the five causes, and a call inside an OpenMP
region stops with its reason. Performance upside is plain: a 4096² float32 `matmul` at 20.4 TFLOP/s on the
GPU and 3.9 TFLOP/s on the CPU device, against 77 GFLOP/s for gfortran's intrinsic.

## Findings

| ID | Priority | Finding | Probe |
| --- | --- | --- | --- |
| U1 | P1 | An out-of-range index reads outside the buffer: the process dies on the CPU, zeros on the GPU | `p11` |
| U2 | P1 | Natural Fortran list forms leak handles and memory, silently | `p05` |
| U3 | P1 | Every graph-building error ends the process; there is no recoverable mode | `p01`, `p03`, `p12` |
| U4 | P2 | A long lazy loop dies at about 250,000 operations (Metal's buffer limit), with no warning in the docs | `p06` |
| U5 | P2 | real64, a Fortran user's default, is second class in four different ways | `p01`, `p09` |
| U6 | P2 | The first expressions a Fortran user types do not compile, with gfortran's messages | `c_compile.F90` |
| U7 | P2 | Small-step costs a porter meets: 181 µs per GPU evaluation, 21 µs per element read, 14 GB/s copies | `p07` |
| U8 | P3 | The documentation is the maintainers', and there is no per-procedure reference | (reading) |
| U9 | P3 | One compiler, one exact version, one platform, one thread | (reading) |
| U10 | P3 | The test suite's tolerances are frozen on one machine; a stock Mac failed `unit_fast` on first run | (the pull) |

### U1 — Index values are not checked, and the failure is memory unsafety

`mlx_take(x, [k])` on a 5-element array, one index per run: `1` and `5` are right; `0` gives element 5 and
`-1` element 4 (the documented wrap); `-5`, `6`, `7`, `100` and `10000` give 0 with status 0 on both devices;
`1000000` ends the process with SIGBUS and `100000000` with SIGSEGV on the CPU device, while the GPU returns 0.
The policy says indices are unchecked and that callers validate; it does not say that a bad index can crash
the program or return a plausible zero. `mlx_slice`, by contrast, refuses bounds outside the array (a stop),
so the two indexing paths a user meets first behave in opposite ways. A newcomer's options: an opt-in checked
mode (a `max`/`min` reduction of the indices against the extent, evaluated once), or a clamp in the graph, and
in any case the crash and the silent zero written into the contract and the quickstart's row D17.

### U2 — The forms that leak are the forms a Fortran programmer writes

1,000 iterations each, `mlx_live_count()` before and after: `mlx_concatenate([a, b])` gains 1 (the result);
`mlx_concatenate([a, exp(b)])` gains 1,000 handles and 250 MB of active memory; `mlx_concatenate([a, b*2.0])`
gains 1,000; `v = exp(a)` on an array of handles gains 1,000. All compile without a warning. The contract lists
them as unsupported and the repository's own code is kept clean by `check_rules.py` (`ctorcall`, `ctorexpr`),
but a user has no such check: the library cannot see the leak, the compiler accepts it, and the README mentions
it in one sentence. Shipping the two rules as a standalone checker a consumer can run on its own sources (or
a CMake helper that runs it), and a "forms to avoid" box with the safe spelling beside each in the quickstart,
would turn a silent leak into a build-time message.

### U3 — No error is recoverable while a graph is built

A shape mismatch (`a + b`, (3) and (4)), a float64 operation on the default device, and a slice bound outside
the array each end the process with `error stop 86` and a clear message. For a batch program that is fine; for
an application, a library embedded in a GUI or Python host, or a long run that wants to fall back to the CPU,
it is not. The checked procedures return a status only at evaluation and transfer. A newcomer would ask for an
opt-in "record and continue" mode (the error kept, the result an empty array, the first checked procedure
reporting the status).

### U4 — The iterative loop written the obvious way

`a = a*0.999 + 0.001` repeated without an evaluation: 100,000 steps build in 1.4 s and evaluate in 0.7 s;
200,000 build in 3.3 s; 300,000 stop at `operator(+)` with `[metal::malloc] Resource limit (499000) exceeded`:
each weak scalar becomes a buffer that the unevaluated graph holds. The contract does not say that a graph must
be evaluated every so often, nor where the limit lies. A sentence in section 8 and the quickstart ("evaluate
inside long loops; every scalar operand is a buffer until then"), and a probe-backed number, would prevent it.

### U5 — Double precision

On the default device (the GPU) `mlx_from` of a real64 array succeeds and the first operation stops. On the CPU
device `sin` of a float64 array returns float64 storage at float32 accuracy (largest error 6.0e-8), and
`irfft(rfft(x))` of a float64 array returns float32 (kind 10), which `mlx_to_alloc` into a real64 array refuses
("differ in kind"): the round trip needs a real32 destination. `mlx_solve` in float64 is exact (residual 7.8e-16).
All of it is documented (quickstart D15 and D16, contract sections 5 and 10), but scattered; for a Fortran
audience, whose default is real64, one short "double precision" section that lists what stops, what keeps the
kind at float32 accuracy, what changes the kind, and what is truly double, belongs near the top.

### U6 — First expressions

`a + 1`, `2*a` and `mlx_from(k) + 1` (an int32 array) do not compile: the scalar operands are real32 and real64
only, and gfortran says "Unexpected derived-type entities in binary intrinsic numeric operator". `print *, a`
fails ("cannot have PRIVATE components"), `if( all(a > 0.) )` fails (a rank-0 array, not a logical), `a(2:3)`
is unclassifiable, and `mlx_from` of complex(real64) has no specific. Each has a reason, but the first two are
what everyone types. Default-integer scalar specifics for the arithmetic operators (the weak-scalar rule
already covers the bitwise functions), a formatted-output procedure (`write(formatted)` or `mlx_print`), and a
logical function form of `all`/`any` for host tests would remove most of the first-hour friction.

### U7 — Costs a porter meets

One tiny operation followed by `mlx_eval`: 181 µs on the GPU, 34 µs on the CPU; the same operations evaluated once
at the end: 3.4 µs and 3.2 µs each. Reading one element with `mlx_item(mlx_slice(a, [i], [i]))`: 21 µs (GPU),
10 µs (CPU). `mlx_from` and `mlx_to` of 256 MB: 13.6 and 14.1 GB/s, against hundreds of GB/s of memory
bandwidth, because each copies into fresh pages; `mlx_alloc` avoids it. None of this is a defect, but a
porter's loop with an evaluation per step is about 50 times slower on the GPU than the same work batched, and
the documents give no such numbers. A short "cost model" table would set expectations.

### U8 — Documentation

The README's status paragraph cites SIMPLE's toys, kernel reports and plan names before a user learns what the
library does; the API table lists names without arguments; the signatures are in the 1,081-line contract or the
source. The general install guide is named `how2use_from_simple.md`. A generated reference (one entry per public
procedure: arguments, kinds, what stops and what returns a status) and a README that leads with use rather than
status would serve the public half of the audience.

### U9 — Toolchain and threads

GNU Fortran only (CMake refuses others), and a consumer must use the producer's exact compiler version and
mlx-c release; macOS on Apple silicon only; one submitting thread, with every call inside an OpenMP region
stopped. Each is a reasoned choice, and each rules out a group of users (ifx, flang and LFortran shops; OpenMP
codes that would call from worker threads). The README names GNU Fortran and macOS; the exact-version rule is only in the install guide, and the
threading consequence for existing OpenMP codes belongs in the README too.

### U10 — The suite on a second machine

`unit_fast` failed on the M2 Ultra right after the pull: `mlx_rope`'s float32 GPU error is 14 to 21 epsilons
here and below 2 on the M5 Ultra, where the tolerance was frozen. The working tree now holds a separate GPU
bound (question 32 for Apple). Every family of parity Phases 5 to 9 was frozen on the M5 Ultra alone (all others passed here); a release
gate run on two GPU generations before a tolerance is frozen would catch it before a user does.
