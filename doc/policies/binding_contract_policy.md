# Binding Contract Policy

How mlx-fortran binds MLX's C API (mlx-c) and what it promises its users: memory order, indices,
lifetime, data movement, kinds, errors, devices, threading, precision, evaluation, memory and growth. It
takes over from decisions 6 to 18, 29, 30 and 39 of the design plan
(`doc/implementation_notes/completed/mlxf_design.md`), which keep their history; from now on this policy is the
truth. How to add a wrapper is the skill `.github/skills/mlxf-binding/SKILL.md`; how the Fortran is
written, the skill `mlxf-modern-fortran`.

## 1. Layers

| layer | what | who sees it |
| --- | --- | --- |
| `build/gen/mlxf_c_types`, `mlxf_c_<header>` | generated at build time from the mlx-c headers linked (`scripts/gen_mlxc_bindings.py`): every handle type `mlxc_<x>` (`bind(c)`, one `type(c_ptr) :: ctx`), the value structs, the enumerators `MLXC_<X>`, the `bind(c)` interfaces `mlxc_<x>` bound to `mlx_<x>` (`_mlx_<x>` become `mlxc_internal_<x>`) | the library only |
| `src/defs/mlxf_defs` | the constants and vocabularies more than one module uses (`MLXF_HARD_ERROR_STATUS`, `MLX_DEVICES`, `MLX_DTYPES`) | the library; users through `mlxf` |
| `src/core/<capability>/mlxf_*` | the hand-written layer, in capability folders of one library target: `runtime/` (`mlxf_libc`, `mlxf_error`, `mlxf_registry`, `mlxf_device`, `mlxf_memory`, `mlxf_version`), `array/` (the module `mlxf_array`: the type, its generics and the interfaces of its procedures; the submodules `mlxf_array_lifetime`, `_transfer`, `_borrow`, `_evaluation`, `_elementwise` implement them), and later one folder per capability (the operations, FFTs, ...) | the library; their `mlxf_` helpers are for the library's own modules |
| `mlxf` | the user module: re-exports the public `mlx_*` names, the intrinsic-name generics and the constants | users |

- The types are one module because the headers' types refer to each other in a cycle (`stream.h` uses
  `vector.h`'s `mlx_vector_stream`, `vector.h` uses `stream.h`'s `mlx_stream`); the interfaces are one module
  per header. The generator skips variadic functions, the float16 and bfloat16 entry points and the
  functions taking `mlx_io_vtable`, and exits with 2 on a C type its one mapping table does not map. The
  build fails unless its generated and skipped names equal the independent list of
  `scripts/list_mlxc_prototypes.py`.
- `mlxf.f90` re-exports no `mlxc_` name (`check_rules.py`, rule `reexport`).
- **Only `mlxf.mod` is installed**, with the library. No other module file reaches a consumer, so a consumer
  cannot name a handle, the registry or a generated interface, and cannot free an object behind the reference
  count; gfortran writes into `mlxf.mod` what a consumer of its public names needs (checked: a consumer's
  `use mlxf` compiles and links, `use mlxf_array` and `use mlxf_c_array` do not compile).
- **One type, one ownership implementation.** `mlx_array` and the procedures that touch its components are
  one module family: the parent module declares the type and the interfaces, its submodules implement them,
  and a helper one submodule needs stays local to it. A stateless operation is a module procedure; a set of
  codes is a constant vocabulary, never an object.
- **One helper per C signature class.** An operation is a call of the helper of its C signature with the
  generated procedure as a procedure argument, whose abstract interface is `bind(c)` with the generated
  intents: `mlxf_unary(r, f, a, proc)` for `int f(mlx_array* res, const mlx_array a, const mlx_stream s)`,
  `mlxf_binary(r, f, a, b, proc)` for the two-operand class. A new class gets one new helper.
- **At most five dummy arguments** per procedure (rule `arity`), in `src/` and `test/`. A procedure that needs
  more takes a spec type: a derived type holding the inputs, constructed and validated once, passed whole.
  Exempt: the generated interfaces and `bind(c)` procedures whose signature C fixes.
- **List arguments are arrays of handles**, `type(mlx_array), intent(in) :: arrays(:)`, never lists of
  optional arguments (`mlx_eval`, `mlx_async_eval`; later `mlx_concatenate`, `mlx_stack`). The caller fills the
  array element by element or writes a constructor of variables (section 4).
- **The public API grows by demonstrated need.** A procedure is wrapped by hand when a pipeline step uses
  it or a test of such a step needs its sibling; the generated layer's breadth is no reason.

## 2. Memory order, indices and positions

- A Fortran array of shape (n1, ..., nr) is the MLX array of shape [nr, ..., n1] over the same bytes:
  `mlx_from` of a (3,5) array gives MLX shape [5,3], and `a%shape()` returns [3,5]. Fortran dimension d is
  MLX axis r - d. `reshape` has Fortran's column-major semantics; broadcasting aligns leading Fortran
  dimensions (to broadcast along dimension 3 an operand has shape (1, 1, n)); an operation along dimension 1
  runs along MLX's last, contiguous axis; `matmul(a, b)` has Fortran semantics on dimensions 1 and 2, is
  batched over dimensions 3 to r and calls `mlx_matmul(b, a)`; `transpose(a)` swaps dimensions 1 and 2 without
  a copy; `mlx_permute(a, order)`: dimension i of the result is dimension `order(i)` of `a`.
- Index values and positions are 1-based in arguments (`mlx_take_along_dim`, `mlx_scatter_add`, slice
  bounds, `kth`) and results (`minloc`, `mlx_argsort`); the wrapper shifts them inside the graph and casts
  index results to int32. Slices are `mlx_slice(a, lower, upper[, stride])` with inclusive bounds from 1.
- A user never writes a C-order shape or a 0-based axis. The one exception is the source of a custom Metal
  kernel, which indexes MLX's row-major, 0-based layout.

## 3. Lifetime

- `mlx_array` holds a private handle and a serial. The registry (`mlxf_registry`) maps each live MLX object
  (its `ctx` address) to its serial and a Fortran-side reference count. A new array is registered with count
  1; the type-bound defined assignment (`impure elemental`, left side `intent(inout)`) shares the object and
  adds one; the `impure elemental` `final` and `kill` subtract one, and the last release frees the MLX
  object. Every public entry first enters (below, section 7), then validates its operands (ctx and serial,
  `mlxf_handle`, a check that does not enter) before calling mlx-c. `mlx_view` and
  `mlx_to` ask whether an array is row-contiguous through mlx-c's internal `_mlx_array_is_row_contiguous` (no
  public entry exists in mlx-c 0.8.0); an mlx-c without it changes the prototype list, and the build names it.
- A declared, never-assigned `mlx_array` is empty: `kill` and `final` skip it, every operation stops on it.
  Assigning an empty `mlx_array` is not an operation: the left side releases its object and becomes empty,
  as an allocatable component becomes unallocated when a derived type is assigned from one whose component
  is unallocated. A derived type holding empty handles may therefore be assigned over one holding live
  handles, with no leak and no stop (the bare assignment is asserted in `unit_array`,
  `test_sections_and_empty`).
  `mlx_is_live(a)` says whether `a` holds a live object; `mlx_live_count()` is the number of live objects, so
  a caller can assert that a loop leaks nothing.
- **A copy made without the defined assignment** shares the object without a count. When the counted owners
  release it, it leaves the registry: the copy's next use stops ("stale mlx_array: copied without defined
  assignment ..."), its finalization frees nothing and counts a stale release. The serial makes an address
  MLX reuses for a new object detectable. Such a copy therefore never frees twice and never reaches MLX after
  its object is gone.
- **Supported**: assignment and self-assignment (`a = a`, `b = (a)`), function results in expressions and as
  actual arguments, `intent(out)` dummies, array constructors **of variables** (`call f([a, b])`), arrays of
  handles assigned **element by element or from a variable** (`v(i) = exp(a)`, `w = a`), derived types with
  **plain** handle components copied by intrinsic assignment (`p2 = p1`), handles leaving scope.
- **Unsupported** (gfortran 16.2 and earlier; reproducers in `doc/compiler_issues/`):
  1. an allocatable handle component copied by the intrinsic assignment of its derived type (the defined
     assignment is skipped: a bitwise copy, diagnosed as above);
  2. `allocate(source=)` and `mold=` on handle types, and array intrinsics (`pack`, `reshape`, `spread`,
     `transpose`, `merge`, `cshift`, `eoshift`, ...) on arrays of handles (bitwise copies, diagnosed);
  3. a function reference inside an array constructor of handles, `[mlx_from(x), exp(a)]`: the result is
     never finalized, so its object leaks (`check_rules.py`, rule `ctorcall`, checks the repository's code);
  4. a whole-array assignment of a function result to an array of handles, `v = exp(a)`: never finalized,
     a leak; assign a variable, or element by element;
  5. intrinsic self-assignment of a derived type holding handles, `w = w`: the components are released
     before they are copied, so the owner ends stale (diagnosed at its next use);
  6. an overlapping section assignment of an array of handles, `v(2:3) = v(1:2)`: the compiler copies the
     right side into a temporary without the defined assignment, and the first element's assignment frees
     the object the second then names, so it stops as stale (no double free). Assign element by element in a
     safe order, or through a second array. It stays unsupported by owner ruling (2026-11-22): making it work
     would need a second assignment path that retains every element before releasing any, for a form a user
     avoids by assigning element by element.
  The registry cannot see leaks 3 and 4: `mlx_live_count()` grows. In this repository's code two rules of
  `check_rules.py` keep use 3 out: `ctorcall` (a library function, `mlx_*` or `mlxf_*`, referenced inside a
  constructor) and `ctorexpr` (an element that refers to a handle and is not a bare designator: `[a*2.0, b]`,
  `[-a, b]`, `[(a), b]`, `[exp(a), b]`).
- **The assignment pattern** for a derived type with allocatable handle components: a type-bound defined
  assignment that copies them element by element.

  ```fortran
  type :: holder
      type(mlx_array), allocatable :: s
      type(mlx_array), allocatable :: arr(:)
    contains
      procedure, private :: holder_assign
      generic            :: assignment(=) => holder_assign
  end type holder

  impure elemental subroutine holder_assign( lhs, rhs )
      class(holder), intent(inout) :: lhs
      class(holder), intent(in)    :: rhs
      integer :: i
      if( allocated(rhs%s) )then
          if( .not. allocated(lhs%s) ) allocate(lhs%s)
          lhs%s = rhs%s
      else if( allocated(lhs%s) )then
          deallocate(lhs%s)
      endif
      if( allocated(lhs%arr) .and. allocated(rhs%arr) )then
          if( size(lhs%arr) /= size(rhs%arr) ) deallocate(lhs%arr)
      endif
      if( allocated(rhs%arr) )then
          if( .not. allocated(lhs%arr) ) allocate(lhs%arr(size(rhs%arr)))
          do i = 1, size(rhs%arr)
              lhs%arr(i) = rhs%arr(i)
          end do
      else if( allocated(lhs%arr) )then
          deallocate(lhs%arr)
      endif
  end subroutine holder_assign
  ```

- The gates: `unit_array`'s leak gate (10,000 iterations of every supported form per device: active memory,
  live count and stale releases equal before and after), `unit_core`'s diagnosis gate (both bypasses, per
  device). No gate test pins a compiler defect: a compiler that fixes one must not fail the build.

## 4. Data in and out

- **Copies are the default.** `mlx_from(x)` copies a Fortran array of any rank (assumed rank, `contiguous`:
  a strided actual is copied in by the compiler) of kind `real32`, `real64`, `complex(real32)`, `int32`,
  `int64` or `logical(c_bool)` into a new MLX array; a zero-size array becomes an empty MLX array without
  taking an address. `mlx_to(y, a)` evaluates `a` and copies it into an existing array of `a`'s kind and
  shape, or into a rank-1 array of its size, which receives the elements in Fortran order (a strided view, a
  transpose, is made contiguous first). Any other shape of the same size returns a status: it would
  reinterpret the data, as a (3,5) array filled from the (5,3) transpose does. `mlx_to_alloc(y, a)`
  (allocatable `y` of rank 1 to 7, the rank of `a`) allocates to `a`'s shape and copies.
- **Writable initialisation.** `a = mlx_alloc(shape, mold, view[, status, zero_copy])` gives an array whose
  storage the caller fills through the Fortran pointer `view`: page-aligned host memory, rounded up to whole
  16 KiB pages, handed to MLX without a copy when Metal accepts it (`zero_copy` says whether it did), else
  copied once, after which `view` points at MLX's copy. Writes through `view` are allowed only until `a` is
  first passed to any library procedure; from then on the storage is read-only, because a lazy graph may read
  it at any later evaluation.
- **Read-only borrowing.** `mlx_view(a, p[, status])` evaluates `a` and points `p` at its storage when `a` is
  row-contiguous (Fortran order) and of `p`'s kind and rank; a strided view returns a status. `p` is valid
  until the next statement that assigns to, kills or ends the scope of `a` (including `a = f(a)`, after
  which MLX may reuse the buffer) and is never written through. A view survives unrelated evaluations (MLX
  donates only buffers no live array references).

## 5. Kinds and scalars

- real32 is float32, real64 float64 (CPU device only), complex(real32) complex64, int32, int64, logical(c_bool)
  bool; `a%kind()` returns one of `MLX_DTYPES%bool`, `%int32`, `%int64`, `%float32`, `%float64`,
  `%complex64`. The vocabularies (`MLX_DEVICES`, `MLX_DTYPES`) and `MLXF_HARD_ERROR_STATUS` are declared in
  `mlxf_defs` and reach users through `mlxf`. complex(real64) has no specific. Nothing converts silently except the scalar rule below.
- On the CPU device MLX computes some float64 operations in float32 (at MLX v0.32.4: `exp`, `sin`, `cos` and
  every FFT); tests hold them to float32 tolerances. CPU float64 `sqrt` meets the float64 bound
  `1e-12 * max(1, abs(sqrt(x)))` against a double-precision reference. A float64 operation built on the
  GPU stops (Metal has no float64): a guard of `object_contracts`.
- **Scalar operands are weak**: a Fortran scalar takes the array's kind when the array is real or complex; a
  real scalar with a complex64 array becomes complex64; an integer or boolean array with a real scalar gives
  float32. A real64 literal never makes a float64 graph. Arithmetic, comparisons and `max` accept real32 and real64 scalars on either side.
  A real32 scalar widened for a float64 array retains its original real32 rounding; a real64 scalar is
  rounded to the array kind. Integer and boolean arrays combined with real scalars produce float32.

## 6. Errors

- The library installs an mlx-c error handler that records MLX's message and returns. Operators and
  functions stop with `mlxf: <procedure>: <message>` on any error (an error MLX reports while building a graph
  is a program error). Every stop is `error stop MLXF_HARD_ERROR_STATUS` (86).
- **Checked procedures** take an optional `integer, intent(out) :: status` and leave the message in
  `mlx_last_error()`: `mlx_eval`, `mlx_async_eval`, `mlx_synchronize`, `mlx_to`, `mlx_to_alloc`, `mlx_view`,
  `mlx_alloc`, `mlx_set_default_device`, `mlx_set_memory_limit`. Without `status` they stop. A failure the
  library finds itself is reported the same way (`mlxf_report`): `mlx_to_alloc` allocates its destination
  with `stat=`, and a destination that cannot be allocated returns a status, the message "the destination
  could not be allocated", and the allocatable unallocated.
- **Recovery.** After a failed evaluation the library and MLX stay usable: an evaluation that needs one
  buffer beyond the device's `max_buffer_length` returns a status whose message names the allocation, and the
  same graph at a batch that fits evaluates (1 GiB in the fast gate; half the failing batch in the sub-suite
  `recovery_half` of `unit_core`, run by name). Over-subscribing unified memory does not fail, it pages: size work
  from `mlx_peak_memory()` and a budget, not by catching failures.
- A procedure C++ calls (the error handler, a deleter, a closure trampoline) never stops; it records and
  returns.

## 7. Devices, threads, precision

- A GPU is present when `mlx_device_count(MLX_DEVICES%gpu) > 0` (not `mlx_metal_is_available`, which says
  only that the backend was compiled in). The default device is MLX's (the GPU when present);
  `mlx_set_default_device(MLX_DEVICES%cpu)` or `(MLX_DEVICES%gpu)` changes it. Without a GPU a Metal build of MLX cannot allocate on
  either device: the first operation that would allocate stops saying so. Explicit streams are not offered.
- **One submitting thread.** Graphs are built and evaluated from one thread. Every public procedure opens
  with the entry (`mlxf_enter`: the one-thread guard, then initialisation on the first call), before it looks
  at an operand, so the guard runs on every path: an empty list of arrays, `mlx_live_count` and
  `mlx_last_error` included (`check_rules.py`, rule `entry`). With OpenMP the guard refuses any call inside a
  parallel region (any level, a team of one included).
- The defined assignment, `kill` and finalization touch shared state only through a live handle: with a
  live handle on either side they refuse a region; between empty handles they run anywhere, so a derived
  type holding empty handles may be copied inside an OpenMP loop. A live handle copied into a region
  (`firstprivate`, a bitwise copy) and released or assigned there stops. These are guards of
  `object_contracts`. gfortran 16.2 finalizes no OpenMP private copy (checked for a `firstprivate` scalar and
  a `firstprivate` allocatable array of handles): the copies are dropped without a release and the original
  keeps its count; a compiler that finalizes them stops at the finalizer's guard instead of updating the
  registry from several threads. The caller's OpenMP code may work on data the library copied out.
- **Precision.** Full precision is `MLX_ENABLE_TF32=0` (CTest sets it); MLX's default lets GPUs with matrix
  units multiply float32 at reduced precision. The library never changes it (mlx-c has no setter);
  `mlxf_runtime_description()` reports MLX's version, the default device, the GPU architecture and the
  variable.

## 8. Evaluation and memory

- `mlx_eval(a | arrays)` evaluates; `mlx_async_eval(a | arrays)` queues and returns; `mlx_synchronize()`
  waits for the work queued on every device; `mlx_to`, `mlx_to_alloc` and `mlx_view` evaluate. The overlap
  pattern, from one thread: queue block n+1 with `mlx_async_eval`, copy out block n, let the CPU consume it.
- Memory controls: `mlx_active_memory()`, `mlx_peak_memory()`, `mlx_reset_peak_memory()`,
  `mlx_cache_memory()`, `mlx_clear_cache()`, `mlx_set_memory_limit(bytes[, previous, status])`,
  `mlx_set_cache_limit(bytes[, previous])`; device facts through `mlx_device_info_size` and
  `mlx_device_info_string` (`max_buffer_length`, `memory_size`, `architecture`, ...).

## 9. Coming with later phases (the contract they keep)

- **Custom Metal kernels** (`mlx_metal_kernel`): configured through a spec type (name, input and output
  names, source, header, grid, threadgroup, template arguments, output shapes in Fortran order), only for a
  measured bottleneck that ordinary or compiled operations cannot handle.


## 10. Operations, matrices and Fourier transforms

- Elementwise arithmetic includes division and unary minus; comparisons return boolean arrays, and
  `.and.`, `.or.`, `.not.` operate on those arrays. `max(a,b)` and `merge(tsource,fsource,mask)` broadcast
  with leading Fortran dimensions aligned. `exp`, `sqrt`, `real`, `aimag`, `conjg` and `mlx_astype(a,dtype)`
  operate elementwise. `real(a)` extracts the float32 real component of complex64 and converts other
  numeric arrays to default real (float32), including real64 input, as Fortran's intrinsic does;
  `cmplx(x,y)` combines two real arrays into complex64 through `x + i*y`. Fortran-style component
  construction is guaranteed for finite parts only: a non-finite imaginary part can introduce NaN into
  the real part through `0*y`. Use `mlx_from` of a host complex array when its non-finite components
  must be preserved.
- `reshape(a,shape)` traverses the input in Fortran order, including a strided input. `transpose` swaps
  dimensions 1 and 2 while preserving batch dimensions. `mlx_permute(a,order)` requires a permutation
  of 1 through rank. `mlx_concatenate(arrays,dim)` takes a nonempty array of handles.
- `mlx_slice(a,lower,upper[,stride])` takes one bound per dimension, inclusive and in range 1 through
  extent; stride defaults to one and may be negative but never zero. Oppositely ordered bounds give
  an empty slice. `mlx_take_along_dim(a,indices,dim)` takes int32/int64 one-based indices of compatible
  rank and shape and shifts them inside the graph. It does not check index values for the Fortran
  range: index 0 becomes MLX index -1 and wraps to the last element of the selected dimension.
  Callers needing strict bounds must validate indices before constructing the graph.
- `sum(a,dim)`, `minval(a,dim)`, `minloc(a,dim)` and `mlx_logsumexp(a,dim)` remove the selected dimension.
  `minloc` returns one-based int32 positions, choosing the first equal minimum. `mlx_logsumexp` uses
  MLX's stable reduction; its test bound is `1e-5 * max(1, abs(logsumexp(x)))`, in log units,
  including CPU float64 (the exponential uses float32 precision). `mlx_cumsum(a,dim)` preserves shape and is forward and inclusive.
- `mlx_zeros(shape[,dtype])` defaults to float32. `mlx_arange(start,stop[,step,dtype])` takes real64
  scalar bounds, defaults to unit step and float32, and excludes `stop`; negative steps are supported.
- `matmul(a,b)` multiplies Fortran dimensions 1 and 2 and broadcasts dimensions 3 and above. Complex
  multiplication does not conjugate either operand; use `conjg` explicitly when needed.
- `mlx_fft`, `mlx_ifft`, `mlx_rfft`, `mlx_irfft` take `(a,dim[,n,norm])`; `mlx_fft2` and `mlx_ifft2`
  take `(a,dims[,n,norm])` with two dimensions and, when supplied, two lengths paired with those
  dimensions. Explicit lengths truncate or zero-pad; omitted lengths use the input extents except
  `irfft`, whose default is `2*(extent-1)` (pass `n` for an odd-length real output).
- `MLX_FFT_NORMS%backward` is the default: the forward transform has negative exponent and no scale,
  the inverse has positive exponent and scale `1/n` (the product of lengths in two dimensions).
  `%forward` scales the forward transform instead; `%ortho` scales both by `1/sqrt(n)`.
  Every FFT wrapper rejects a `norm` outside these three `MLX_FFT_NORMS` values before calling mlx-c.
  `rfft` stores `floor(n/2)+1` complex values. MLX transforms use float32/complex64 even for CPU float64
  input, so the FFT tests use the documented float32 norm bound against independent double DFTs.


## 11. Fortran callbacks and graph compilation

`f = mlx_function(callback)` (or `call f%new(callback)`) owns an mlx-c closure. Its callback is a
checked Fortran subroutine:

```fortran
subroutine callback(inputs, outputs, status)
    type(mlx_array), intent(in) :: inputs(:)
    type(mlx_array), allocatable, intent(out) :: outputs(:)
    integer, intent(out) :: status
end subroutine callback
```

- On success, allocate `outputs`, assign its elements individually and set `status=0`. On failure,
  return a nonzero status; outputs are discarded. A zero status with unallocated outputs or an empty/stale
  output handle is converted to a failure. An allocated zero-length output list is distinct from an
  unallocated list. Validate callback inputs before building a graph and use `status=` on checked calls;
  callbacks must return errors rather than stop. The wrapper cannot intercept a user callback's `stop`
  or a programming error in an unchecked graph-building operation.
- `call f%apply(inputs,outputs[,status])` applies the closure. It replaces the caller's allocatable output
  list, returns checked errors and publishes no outputs on failure. Without `status`, failure stops only
  after the C call has returned. The callback and its captured host state must remain valid while any
  function copy can call it; a module procedure is the normal choice. A callback may apply another
  function with `status=` and propagate that status; the apply entry and C trampoline are recursive,
  including during compiled tracing.
- `g = mlx_compile(f[,shapeless])` builds a compiled closure. `shapeless` defaults to false; true permits
  the same traced graph to serve different extents at the same rank/dtype. The callback must express
  shape-independent graph operations for that use. Choose the device before tracing and use a separately
  created function for each device. Compilation does not promise numerical equality across arbitrary
  shape changes or fused floating-point expressions.
- `f%trace_count()` counts callback invocations shared by copies and compiled derivatives of `f`.
  Uncompiled applies also increment it. Taking the count difference around compiled calls measures tracing;
  the two-tile test observes one trace per device. This is object state, not a global counter.
- Function assignment retains the registered closure; `kill` is idempotent and finalization releases it.
  The compiled closure keeps the callback payload alive after the original function is killed. The
  existing registry also tracks closures, so `mlx_live_count()` includes both arrays and functions.
  Assignment between empty functions, empty `kill` and empty finalization touch no shared state and
  are safe inside an OpenMP region; they do not initialize the runtime. A live handle on either side
  of assignment, or on release, still invokes the one-thread guard.
  The unsupported bitwise-copy and temporary-result forms of section 3 also apply to function handles.
- A checked subroutine avoids a GNU Fortran 16.2 use-after-free when an allocatable array function result
  of a finalizable type is consumed as an actual argument: the compiler frees the result before invoking
  its finalizer. `doc/compiler_issues/gfortran_finalize_allocatable_array_result.f90` reproduces that
  independently of MLX and includes the passing explicit-output control. The owner approved this callback
  interface on 2026-11-22.
  No `grad`, `vjp` or `vmap` is wrapped.
