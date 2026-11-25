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
  it, a test of such a step needs its sibling, or the parity ledger `scripts/mlxc_parity.txt` lists its mlx-c
  function as pending (parity with mlx-c is a goal: MLX's documented API is the need); the generated layer's
  breadth is no other reason.

## 2. Memory order, indices and positions

- A Fortran array of shape (n1, ..., nr) is the MLX array of shape [nr, ..., n1] over the same bytes:
  `mlx_from` of a (3,5) array gives MLX shape [5,3], and `a%shape()` returns [3,5]. Fortran dimension d is
  MLX axis r - d. `reshape` has Fortran's column-major semantics; broadcasting aligns leading Fortran
  dimensions (to broadcast along dimension 3 an operand has shape (1, 1, n)); an operation along dimension 1
  runs along MLX's last, contiguous axis; `matmul(a, b)` has Fortran semantics on dimensions 1 and 2, is
  batched over dimensions 3 to r and calls `mlx_matmul(b, a)`; `transpose(a)` swaps dimensions 1 and 2 without
  a copy; `mlx_permute(a, order)`: dimension i of the result is dimension `order(i)` of `a`.
- MLX's row-major order of the reversed shape is Fortran's array element order. A function that flattens when
  MLX is given no axis (`mlx_sort`, `mlx_argsort`, `mlx_partition`, `mlx_topk`, the scans, `mlx_repeat`,
  `mlx_concatenate`, `mlx_flatten`) therefore acts on the elements in array element order and returns a rank-1
  array; `maxloc(a)` and `minloc(a)` turn MLX's position in that order into Fortran subscripts.
- A matrix argument is the Fortran matrix in dimensions 1 and 2, which MLX sees transposed. The wrappers
  translate so that "lower", "upper" and a diagonal's number mean what they mean in Fortran: diagonal k > 0
  holds the elements (i, i + k), above the main diagonal. `mlx_tril(a, k)` calls MLX's `triu` with -k and
  `mlx_triu` its `tril`; `mlx_diag` and `mlx_eye` pass -k; `mlx_tri` adds one transpose node (a view) to MLX's
  triangle. `mlx_diagonal` and `mlx_trace` take the two dimensions by number (1 and 2 by default).
- Index values and positions are 1-based in arguments (`mlx_take_along_dim`, `mlx_scatter_add`, slice
  bounds, `kth` of `mlx_partition` and `mlx_argpartition`, the cut positions of `mlx_split`) and results
  (`minloc`, `maxloc`, `mlx_argsort`, `mlx_argpartition`); the wrapper shifts them inside the graph and casts
  index results to int32. `mlx_as_strided`'s `offset` is a count of elements skipped, not a position, and its
  strides are in elements per Fortran dimension. Slices are `mlx_slice(a, lower, upper[, stride])` with inclusive bounds from 1.
- A user never writes a C-order shape or a 0-based axis. The one exception is the source of a custom Metal
  kernel, which indexes MLX's row-major, 0-based layout (section 12 says how a Fortran array reads there).

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
  it at any later evaluation. A shape whose size in bytes does not fit `c_size_t` is refused before anything
  is allocated. MLX's deleter frees the buffer, at once when MLX copies it; it runs with a small ownership
  record, so a failed call frees the buffer only when the deleter has not, never twice and never leaked.
- **Read-only borrowing.** `mlx_view(a, p[, status])` evaluates `a` and points `p` at its storage when `a` is
  row-contiguous (Fortran order) and of `p`'s kind and rank; a strided view returns a status. `p` is valid
  until the next statement that assigns to, kills or ends the scope of `a` (including `a = f(a)`, after
  which MLX may reuse the buffer) and is never written through. A view survives unrelated evaluations (MLX
  donates only buffers no live array references). After any refused `mlx_view` or `mlx_alloc` the pointer is
  disassociated, a pointer of rank above 7 included.
  The owner is a named variable: a view of an expression, `call mlx_view(exp(a), p)`, dangles when the
  statement ends, because the expression's result is finalized there (the library cannot detect it).
  `w = exp(a)`, then `call mlx_view(w, p)`, keeps `p` valid while `w` is unchanged.

## 5. Kinds and scalars

- real32 is float32, real64 float64 (CPU device only), complex(real32) complex64, int8, int16, int32, int64,
  logical(c_bool) bool: these eight kinds move through `mlx_from`, `mlx_to`, `mlx_to_alloc`, `mlx_view`,
  `mlx_alloc` and `mlx_item`. `a%kind()` returns one of `MLX_DTYPES%bool`, `%int8`, `%int16`, `%int32`,
  `%int64`, `%float32`, `%float64`, `%complex64`, or a dtype that exists on the device only: `%uint8`,
  `%uint16`, `%uint32`, `%uint64`, `%float16`, `%bfloat16`. Fortran has no standard kind for those six:
  `mlx_astype` converts to and from them, operations take and return them, and a transfer of one is refused
  ("differ in kind") until it is converted.
- `call mlx_item(a, value[, status])` evaluates an array of one element (rank 0, or any rank of size 1) and
  returns the element in a scalar of `a`'s kind. It is a checked procedure: another kind or another size is
  refused through `status`, and nothing is converted. The vocabularies (`MLX_DEVICES`, `MLX_DTYPES`) and `MLXF_HARD_ERROR_STATUS` are declared in
  `mlxf_defs` and reach users through `mlxf`. complex(real64) has no specific. Nothing converts silently except the scalar rule below.
- On the CPU device MLX computes some float64 operations in float32 (at MLX v0.32.4: `exp`, `sin`, `cos`,
  `erf`, `mlx_erfinv`, `mlx_sigmoid`, `mlx_logaddexp`, `mlx_logsumexp`, `mlx_logcumsumexp`, `mlx_softmax` and
  every FFT); tests hold them to float32 tolerances.
- On the GPU, MLX v0.32.4's float32 `expm1` loses accuracy as its argument grows: an error relative to
  `max(1, |expm1(x)|)` of about 20 float32 epsilons at x = 0.5 and 168 at x = 10, against below 1 on the CPU
  (`doc/collaboration/apple_questions.md`, question 20; `scripts/probes/expm1_gpu_probe.c`). `mlx_expm1` is
  kept; where a GPU result near 1e-5 relative is not good enough, compute it on the CPU device. CPU float64 `sqrt` meets the float64 bound
  `1e-12 * max(1, abs(sqrt(x)))` against a double-precision reference. A float64 operation built on the
  GPU stops (Metal has no float64): a guard of `object_contracts`.
- **Scalar operands are weak**: a Fortran scalar takes the array's kind when the array is real or complex
  (float16 and bfloat16 included: the scalar is made in the half kind, rounded through float32, so `h + 1.0`
  stays half precision); a real scalar with a complex64 array becomes complex64; an integer or boolean array with a real scalar gives
  float32. A real64 literal never makes a float64 graph. Arithmetic (`**` included), comparisons, `max`, `min`,
  `atan2`, `modulo`, `mlx_logaddexp`, `mlx_floor_divide` and `mlx_clip`'s bounds accept real32 and real64
  scalars on either side, in the intrinsic's argument order. The bitwise functions (`iand`, `ior`, `ieor` on
  either side; `shiftl`, `mlx_right_shift` as the shift) accept a default integer scalar, which takes the
  array's integer kind.
  A real32 scalar widened for a float64 array retains its original real32 rounding; a real64 scalar is
  rounded to the array kind. Integer and boolean arrays combined with real scalars produce float32.

## 6. Errors

- The library installs an mlx-c error handler that records MLX's message and returns. Operators and
  functions stop with `mlxf: <procedure>: <message>` on any error (an error MLX reports while building a graph
  is a program error). Every stop is `error stop MLXF_HARD_ERROR_STATUS` (86).
- **Checked procedures** take an optional `integer, intent(out) :: status` and leave the message in
  `mlx_last_error()`: `mlx_eval`, `mlx_async_eval`, `mlx_synchronize`, `mlx_to`, `mlx_to_alloc`, `mlx_view`,
  `mlx_alloc`, `mlx_set_default_device`, `mlx_set_memory_limit`, `mlx_device_info_size`,
  `mlx_device_info_string`, and the `apply` of `mlx_function` and of `mlx_metal_kernel`. Without `status` they
  stop. A failure the
  library finds itself is reported the same way (`mlxf_report`). **`mlx_to_alloc` changes its destination only
  on success:** it checks the kind and the rank before touching it, fills a new allocation (made with
  `stat=`), and moves it into the destination when the copy succeeds. On any failure that returns a status
  the destination keeps its allocation and its values (or stays unallocated); a destination that cannot be
  allocated gives the message "the destination could not be allocated". The old and the new allocation exist
  together during the copy.
- **Recovery.** After a failed evaluation the library and MLX stay usable: an evaluation that needs one
  buffer beyond the device's `max_buffer_length` returns a status whose message names the allocation, and the
  same graph at a batch that fits evaluates (1 GiB in the fast gate; half the failing batch in the sub-suite
  `recovery_half` of `unit_core`, run by name). Over-subscribing unified memory does not fail, it pages: size work
  from `mlx_peak_memory()` and a budget, not by catching failures.
- A procedure C++ calls (the error handler, a deleter, a closure trampoline) never stops; it records and
  returns. That holds for the trampoline's own work too: importing its inputs (mlx-c, the registry, an
  allocation) and exporting its outputs report a status.
- A device type other than `MLX_DEVICES%cpu` or `%gpu` is refused before it reaches mlx-c, which indexes a
  table with it; likewise a dtype outside `MLX_DTYPES` (`mlx_astype`, `mlx_bitcast`, `mlx_zeros`,
  `mlx_arange`), which stops (guards `guard_dtype_*` of `object_contracts`). The device information is -1 (or empty) with status 0 when the device or the key is absent;
  a failure inside MLX is an error, never that value alone.

## 7. Devices, threads, precision

- A GPU is present when `mlx_device_count(MLX_DEVICES%gpu) > 0` (not `mlx_metal_is_available`, which says
  only that the backend was compiled in). The default device is MLX's (the GPU when present);
  `mlx_set_default_device(MLX_DEVICES%cpu)` or `(MLX_DEVICES%gpu)` changes it. Without a GPU a Metal build of MLX cannot allocate on
  either device: the first operation that would allocate stops saying so. Explicit streams are not offered.
  One choice of stream is the library's own: the factorisations, inverses, determinants, eigenvalues and
  solvers of section 10, which MLX implements on the CPU only, always run on the CPU's default stream.
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

- **Custom Metal kernels** (`mlx_metal_kernel`) are delivered: section 12. They are configured through a spec
  type and kept for a measured bottleneck that ordinary or compiled operations cannot handle.


## 10. Operations, matrices and Fourier transforms

- Elementwise arithmetic includes division and unary minus. **`/` is MLX's true division, not Fortran's:** two
  integer arrays divide to float32 (7 / 2 is 3.5), where Fortran truncates; `mlx_floor_divide(a,b)` keeps the
  integer kind and floors. Comparisons return boolean arrays, and
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
  of 1 through rank. `mlx_concatenate(arrays[,dim])` takes a nonempty array of handles; without `dim` it
  joins the arrays' elements, each in array element order, into a rank-1 array.
- `mlx_slice(a,lower,upper[,stride])` takes one bound per dimension, inclusive and in range 1 through
  extent; stride defaults to one and may be negative but never zero. Oppositely ordered bounds give
  an empty slice. `mlx_take_along_dim(a,indices,dim)` takes integer one-based indices of compatible
  rank and shape and shifts them inside the graph. It does not check index values for the Fortran
  range: index 0 becomes MLX index -1 and wraps to the last element of the selected dimension.
  Callers needing strict bounds must validate indices before constructing the graph.
- `mlx_take(a,indices,dim)` gathers whole slices: the indices' Fortran shape takes the place of dimension
  `dim`, `r(.., i1, .., ik, ..) = a(.., indices(i1, .., ik), ..)`. Its indices are one-based, shifted in
  the graph and unchecked, as `mlx_take_along_dim`'s (0 wraps to the last slice). Gathering a slab per index
  is cheaper than `mlx_take_along_dim`, which computes one index per output element. `mlx_take(a,indices)`
  without `dim` takes one-based positions in array element order and has the indices' shape.
- **Gather and scatter.** `mlx_gather(a,indices,dim,slice_sizes)` and `mlx_gather(a,indices,dims,slice_sizes)`
  (an array of index arrays, one per listed dimension) take slabs of `a`: `slice_sizes` gives the slab's
  extent along every dimension of `a`, the indices its one-based start along the listed ones. The result
  has the slab's shape followed by the index arrays' shape (MLX's layout, index dimensions first, read in
  Fortran order). `mlx_scatter(a,indices,updates,dim)` / `(a,indices,updates,dims)` write slabs back:
  `updates` has `a`'s shape with extent 1 along the listed dimensions, followed by the index arrays' shape;
  where positions repeat, which update stays is undefined. `mlx_scatter_add`, `mlx_scatter_max`,
  `mlx_scatter_min` and `mlx_scatter_prod` combine instead (repeats accumulate).
  `mlx_put_along_dim(a,indices,values,dim)` writes element by element, the inverse of `mlx_take_along_dim`.
  `mlx_scatter_add(a,indices,updates,dim)` with one index array chooses by rank: updates of rank
  `rank(indices) + rank(a)` are slabs; otherwise it adds element by element as `mlx_put_along_dim` writes
  (MLX's `scatter_add_axis`). No index is checked against the extents. Index arrays are of any integer
  dtype.
- `mlx_masked_scatter(a,mask,src)` replaces the elements where the boolean `mask` holds by the elements of
  `src`, taken in array element order; a mask of lower rank has the shape of `a`'s last dimensions.
- `mlx_slice(a,start,dims,slice_sizes)` is the dynamic slice: `start` is a rank-1 integer array of the graph
  holding one one-based position per listed dimension, `slice_sizes` the extents along every dimension; a
  dynamic section that leaves the array is not checked and reads or writes outside it.
  `mlx_slice_update(a,update,lower,upper[,stride])` returns `a` with the section replaced by `update`
  (bounds as `mlx_slice`'s; `update` broadcasts to the section with leading dimensions aligned);
  `mlx_slice_update_add`, `_max`, `_min`, `_prod` combine with the section instead;
  `mlx_slice_update(a,update,start,dims)` is the dynamic form.
- `mlx_searchsorted(sorted,values[,side])` returns, with the values' shape, the one-based int32 positions
  from 1 to n + 1 at which each value would be inserted into the ascending rank-1 `sorted`; `side` is
  `'left'` (the default, before equal elements) or `'right'`.
- `call mlx_unique(a,size,results[,fill])` returns four arrays: the distinct values in ascending order in
  `size` slots (a graph's shapes are fixed, so the caller gives the number of slots; unused ones hold
  `fill`, the smallest value by default; a smaller `size` truncates), the one-based position in array
  element order of each value's first occurrence, the one-based slot of every element (with `a`'s shape),
  and the count of each value (zero in an unused slot).
- `mlx_bitcast(a,dtype)` reads `a`'s bytes as another dtype and converts no value (MLX's `view`; the name
  `mlx_view` is the Fortran pointer view of section 4). Where the item sizes differ, the first Fortran
  dimension scales by their ratio: a float32 `(2n, ...)` array whose pairs along dimension 1 are (real,
  imaginary) reads as complex64 `(n, ...)`, and back. A contiguous input is reinterpreted in place; MLX
  copies a strided one first.
- **Reductions** take one dimension, a list or neither: `sum`, `product`, `maxval`, `minval`, `all`, `any`,
  `count`, `mlx_mean`, `mlx_median`, `mlx_logsumexp` are `f(a[,dim][,keepdims])` and `f(a,dims[,keepdims])`;
  `mlx_var` and `mlx_std` add `ddof` (the divisor is the count less `ddof`, 0 by default). Without `dim` or
  `dims` every dimension is reduced and the result is rank 0. The reduced dimensions are removed, or kept with
  extent 1 under `keepdims=.true.`. `all`, `any` and `count` treat a nonzero element as true; `count` is
  int32, `all` and `any` boolean; `mlx_mean` of an integer array is float32. Optional arguments are passed by
  keyword (`sum(a, keepdims=.true.)`). `mlx_logsumexp` uses MLX's stable reduction; the first test
  of its `(a,dim)` form keeps the bound `1e-5 * max(1, abs(logsumexp(x)))`, in log units, including CPU
  float64 (the exponential uses float32 precision).
- `minloc(a,dim[,keepdims])` and `maxloc(a,dim[,keepdims])` return one-based int32 positions, choosing the
  first equal extremum; for a zero-size array they return zeros, as Fortran's do, where MLX's argmin and
  argmax refuse the array. `minloc(a)` and `maxloc(a)` return the subscripts of the first extremum in array
  element order as a rank-1 int32 array of size rank, as Fortran's do.
- **Scans**: `mlx_cumsum`, `mlx_cumprod`, `mlx_cummax`, `mlx_cummin`, `mlx_logcumsumexp` are
  `f(a[,dim][,reverse][,inclusive])`. They preserve the shape along `dim`; without `dim` they scan the
  elements in array element order and return rank 1. `reverse` scans from the last element; an exclusive scan
  leaves each element out of its own result (the first is the scan's identity: 0 for a sum, 1 for a product).
  MLX's optional result dtype is not offered.
- `mlx_softmax(a[,dim][,precise])` and `mlx_softmax(a,dims[,precise])`: along dimension 1 when no dimension is
  given, jointly over a list.
- **Sorting**: `mlx_sort(a[,dim])`, `mlx_argsort(a[,dim])`, `mlx_partition(a,kth[,dim])`,
  `mlx_argpartition(a,kth[,dim])`, `mlx_topk(a,k[,dim])`. `kth` is the one-based sorted position put in
  place (below 1 stops, as a cut position of `mlx_split` below 1 does); positions returned are one-based int32. `mlx_topk` returns the k largest values (MLX returns no
  positions), in no defined order. `mlx_argsort` kept equal elements in their original order in every test
  on both devices (lines of 3 to 5 elements with ties); MLX documents no stability, so do not rely on it.
- **Shape**: `mlx_squeeze(a[,dim])`/`(a,dims)`, `mlx_expand_dims(a,dim)`/`(a,dims)` (positions in the
  result), `mlx_flatten(a[,start_dim,end_dim])` (merges the dimensions in array element order),
  `mlx_unflatten(a,dim,shape)`, `mlx_broadcast_to(a,shape)`, `mlx_tile(a,reps)` (one repetition count per
  dimension, the first dimensions when fewer are given), `mlx_repeat(a,repeats[,dim])`,
  `mlx_flip(a[,dim])`/`(a,dims)` (every dimension when none is given), `mlx_movedim(a,source,destination)`,
  `mlx_swapdims(a,dim1,dim2)`, `mlx_diff(a[,n,dim])` (first difference along dimension 1 by default),
  `mlx_atleast_1d`, `mlx_atleast_2d` ((n) becomes (n, 1)) and `mlx_atleast_3d` (MLX's rule read in Fortran
  order: (n) becomes (1, n, 1) and (m, n) becomes (1, m, n)). `cshift(a,shift[,dim])` is Fortran's: element i
  of the result is element i + shift, along dimension 1 by default (MLX's roll by -shift);
  `cshift(a,shifts,dims)` shifts each listed dimension. `mlx_pad(a,width[,value,mode])` pads every side of
  every dimension, `mlx_pad(a,low,high[,value,mode])` takes the widths before and after each Fortran
  dimension; `value` is an array (zero by default) and `mode` goes to MLX as given (`'constant'` by default; `'edge'`
  is tested).
  `mlx_as_strided(a,shape,strides[,offset])`: element (i1, ..., ir) of the result is element
  `1 + offset + sum((i_d - 1)*strides(d))` of `a` in array element order (a strided `a` is made contiguous
  first, since MLX strides over the buffer); nothing checks that it lies inside.
  `mlx_number_of_elements(a[,dims,inverted,dtype])` is the product of the extents as a rank-0 array.
- **Lists of arrays** come back through an allocatable `intent(out)` array of handles, so these are
  subroutines: `call mlx_split(a,num,parts[,dim])` (equal parts) and `call mlx_split(a,indices,parts[,dim])`
  (cut before each one-based position: `[4, 7]` gives 1:3, 4:6 and 7:), `call mlx_unstack(a,parts[,dim])`,
  `call mlx_broadcast_arrays(arrays,results)`, `call mlx_meshgrid(arrays,grids[,sparse])`. An omitted `dim`
  is the last dimension for `mlx_split`, `mlx_unstack` and `mlx_stack(arrays[,dim])` (MLX's first axis), where
  `dim` of `mlx_stack` is the new dimension's position in the result. `mlx_meshgrid` uses matrix indexing in
  the Fortran view: grid i has shape (n1, ..., nk) and varies along dimension i (extent 1 elsewhere when
  sparse); MLX's `indexing` argument is not offered (its `'xy'` is the same call with the first two arrays,
  and the first two grids returned, exchanged).
- **Matrices and constructors**: `mlx_diag(a[,k])`, `mlx_diagonal(a[,offset,dim1,dim2])` (the diagonal is
  dimension 1 of the result, the other dimensions follow in order), `mlx_trace(a[,offset,dim1,dim2,dtype])`,
  `mlx_tril(a[,k])`, `mlx_triu(a[,k])` (on dimensions 1 and 2 of every batch), `mlx_identity(n[,dtype])`,
  `mlx_eye(n[,m,k,dtype])` and `mlx_tri(n[,m,k,dtype])` (shape (n, m)), all in the Fortran view of section 2.
  `mlx_linspace(start,stop[,num,endpoint,dtype])` takes real64 bounds, 50 points and float32 by default and
  includes `stop` unless `endpoint=.false.`. `mlx_bartlett(m)`, `mlx_blackman(m)`, `mlx_hamming(m)` and
  `mlx_hanning(m)` are float32 windows of m points.
- **Elementwise functions** keep the intrinsic's name where the value semantics agree, with an array result
  whose kind follows MLX's rules: `abs`, `sin`, `cos`, `tan`, `sinh`, `cosh`, `tanh`, `log`, `log10`, `erf`,
  `asin`, `acos`, `atan`, `asinh`, `acosh`, `atanh`, `atan2(y,x)`, `modulo(a,p)`, `min(a,b)`, `iand`, `ior`,
  `ieor`, `not`, `shiftl`, and the operators `**`, `.eqv.`, `.neqv.` and unary `+`. `floor`, `ceiling` and
  `aint` (truncation) keep the input's float kind, unlike Fortran's integer `floor` and `ceiling`.
  `modulo` takes the divisor's sign, as Fortran's; `mlx_floor_divide(a,b)` is `floor(a/b)` and
  `call mlx_divmod(a,b,quotient,remainder)` returns both from one node. `mlx_round(a[,decimals])` rounds
  halves to even (0.5 to 0, 2.5 to 2), unlike `anint` and `nint`; `mlx_sign(a)` is the signum of one argument,
  unlike Fortran's `sign(a,b)`. `mlx_right_shift` is arithmetic on signed integers (Fortran's `shifta`, not
  the logical `shiftr`). The other names are MLX's: `mlx_sigmoid`, `mlx_square`, `mlx_reciprocal`,
  `mlx_rsqrt`, `mlx_expm1`, `mlx_log1p`, `mlx_log2`, `mlx_erfinv`, `mlx_degrees`, `mlx_radians`,
  `mlx_logaddexp`, `mlx_clip(a,a_min,a_max)`, `mlx_nan_to_num(a[,nan,posinf,neginf])` (NaN to 0 and the
  infinities to the kind's largest finite values by default), `mlx_stop_gradient` and `mlx_copy` (a new
  graph node; assignment shares the node instead).
- **Predicates and tests** return boolean arrays: `mlx_isnan`, `mlx_isinf`, `mlx_isfinite`, `mlx_isposinf`,
  `mlx_isneginf`; `mlx_isclose(a,b[,rtol,atol,equal_nan])` is `|a-b| <= atol + rtol*|b|` with NumPy's
  defaults rtol = 1e-5, atol = 1e-8 and NaNs unequal; `mlx_allclose` (same arguments) and
  `mlx_array_equal(a,b[,equal_nan])` (same shape and values, any dtypes) return rank-0 boolean arrays.
- **Dimension 1 by default.** A function whose MLX default is the last axis (a softmax, `mlx_diff`, the norms
  and `rope` of `fast`, attention) acts on Fortran dimension 1, the contiguous one, when no dimension is given.
- `mlx_zeros(shape[,dtype])` and `mlx_ones(shape[,dtype])` default to float32.
  `mlx_full(shape,vals[,dtype])` takes an array (broadcast with leading dimensions aligned, of its kind by
  default) or a scalar (float32 for a real value, int32 for an integer one, by default).
  `mlx_zeros_like(a[,dtype])`, `mlx_ones_like(a[,dtype])` and `mlx_full_like(a,vals[,dtype])` take `a`'s shape
  and, by default, its kind. A float64 fill keeps a real32 value's rounding. `mlx_arange(start,stop[,step,dtype])` takes real64
  scalar bounds, defaults to unit step and float32, and excludes `stop`; negative steps are supported.
- `matmul(a,b)` multiplies Fortran dimensions 1 and 2 and broadcasts dimensions 3 and above. Complex
  multiplication does not conjugate either operand; use `conjg` explicitly when needed. **MLX multiplies
  floating-point and complex matrices only:** operands whose promoted kind is an integer kind (two integer
  arrays) stop, unlike Fortran's integer `matmul`; convert with `mlx_astype` first. An integer operand with a
  real one is promoted and multiplied.
- **Products of chosen, masked and segmented matrices.** Three products of real matrices in the Fortran view,
  with no transpose and no copy: the operands are exchanged, as for `matmul` (MLX's product of the transposes
  is the transpose of the Fortran product), and the lists and masks are exchanged with them; the only added
  node is the shift of a list or of the segments to MLX's 0-based values. With a list, a mask or segments,
  complex and integer operands stop (without, the first two are `matmul`, which takes complex operands and
  refuses two integer ones).
  - `mlx_gather_mm(a,b[,lhs_indices,rhs_indices,sorted_indices])`:
    `r(:,:,i) = matmul(a(:,:,lhs_indices(i)), b(:,:,rhs_indices(i)))`. An index is the one-based number of a
    matrix in array element order over dimensions 3 and up of its operand: matrix 4 of a (m, k, 3, 2) array is
    `a(:,:,1,2)`. The two index arrays broadcast together with leading dimensions aligned, and their shape
    follows dimensions 1 and 2 of the result. An absent list takes the operand's matrices in order, with the
    shape of its batch dimensions; with neither list the result is `matmul`'s, bit for bit.
    `sorted_indices=.true.` tells MLX that the one list given is ascending. Index arrays are of any integer
    dtype, shifted in the graph and unchecked, as every index.
  - `mlx_block_masked_mm(a,b[,block_size,mask_out,operand_masks])`: `matmul(a,b)`, batched, with blocks of
    `block_size` rows and columns left out (32 or 64, MLX's two sizes; 64 by default). A mask has one element
    per block, `ceiling(extent/block_size)` along each of its two matrix dimensions, then the batch
    dimensions: `mask_out(i,j)` for block (i, j) of the result, `operand_masks(1)` for the blocks of `a` (rows
    by inner dimension) and `operand_masks(2)` for those of `b` (inner dimension by columns), both applied
    before the product and given together (an all-true mask leaves an operand whole). A boolean mask keeps a
    block or zeroes it; a real mask multiplies it. A block a mask drops is exactly zero. Without masks the
    result is `matmul`'s, bit for bit.
  - `mlx_segmented_mm(a,b,segments)`: two matrices (rank 2) cut along the inner dimension.
    `segments(1,i)` and `segments(2,i)` are the first and the last inner index of segment i, inclusive and
    one-based, and `r(:,:,i) = matmul(a(:,s1:s2), b(s1:s2,:))`; a last index below the first gives zeros, as
    an empty section does (measured on both devices for gaps up to 299). The segments' dimensions 2 and up
    follow dimensions 1 and 2 of the result. The wrapper checks what MLX does not: the two ranks, equal
    inner extents, and a first dimension of extent 2 for `segments` (the shift of the bounds would otherwise
    broadcast a (1, n) array into pairs). The bounds themselves are values of the graph and are not checked
    against the inner extent, as no index is.
  - MLX v0.32.4 evaluates the gathered and the masked product in float32 only: built on float64 operands they
    fail the evaluation on the CPU with a status ("Currently only supports float32"). The segmented product is
    float64 on the CPU. The tests (`linalg_mm` of `unit_linalg`) judge an element by its error relative to
    `max(1, (|a| |b|)(i,j))` against real64 `matmul` of the same sections, at 4 epsilons of the result kind.
- **Other products.** The exchange of operands that serves `matmul` also puts the dimensions of an inner
  product, an outer product and a contraction in Fortran's order, `a`'s before `b`'s; none adds a node.
  - `mlx_addmm(c,a,b[,alpha,beta])`: `alpha*matmul(a,b) + beta*c` in one node, `c` broadcast, both factors
    real32 and 1 by default; a rank-1 `a` is a row and a rank-1 `b` a column, as for Fortran's `matmul`.
  - `mlx_inner(a,b)` sums over dimension 1 of both, without conjugation: `r(i...,j...)` is the sum over k of
    `a(k,i...)*b(k,j...)`. `mlx_outer(a,b)` is `r(i,j) = a(i)*b(j)` over the elements of each in array element
    order. `mlx_kron(a,b)` is the Kronecker product, `r((i-1)*p+k,(j-1)*q+l) = a(i,j)*b(k,l)` for a (p, q)
    `b`; a lower rank counts with trailing extents of 1.
  - `mlx_vecdot(a,b[,dim])` is the dot product along `dim` (1 by default) of two arrays of one rank, the first
    conjugated: Fortran's `dot_product`, batched. `mlx_cross(a,b[,dim])` is the cross product of the vectors of
    3 elements along `dim` (1 by default); vectors of 2 count with a third component of zero and give 3. The
    other dimensions broadcast, also between different ranks (the dimension reaches MLX as its axis `-dim`).
  - `mlx_tensordot(a,b[,n])` contracts the last `n` dimensions of `a` with the first `n` of `b` in order (2 by
    default; 1 is `matmul` for matrices); `mlx_tensordot(a,b,dims_a,dims_b)` contracts `dims_a(i)` with
    `dims_b(i)`. The result has the remaining dimensions of `a`, then those of `b`.
  - `mlx_einsum(subscripts,operands)`: each operand has one letter per dimension **in Fortran's order**, a
    repeated letter is summed over, and `...` stands for the dimensions not named, which broadcast aligned from
    the first. After `->` come the result's letters; without it the result has the letters that occur once,
    capitals first and each case in alphabetical order, then the ellipsis. So `'ij,jk->ik'` is `matmul`,
    `'ij->ji'` the transpose and `'ij...,jk...'` the batched product with the batch last. The wrapper reverses
    every term for MLX and always names the result (MLX's own default would read in reverse order).
  - `mlx_hadamard_transform(a[,scale])` is the Walsh-Hadamard transform along dimension 1, whose extent n is a
    power of two, times `scale` (real32; `1/sqrt(n)` by default, its own inverse).
  - MLX v0.32.4 evaluates the Hadamard transform in float32 only: on a float64 array the graph builds and the
    evaluation fails with a status ("[hadamard] Unsupported type"). The others are float64 on the CPU. The
    tests (`linalg_products`) judge an element by its error relative to `max(1,` the same product of the
    magnitudes`)` against real64 loops, at 4 epsilons of the result kind.
- **Matrices: factorisations, inverses, determinants, eigenvalues and solvers.** A Fortran matrix is
  dimensions 1 and 2, further dimensions a batch, and MLX sees its transpose. What that costs, per function:
  - nothing: `mlx_inv(a)`, `mlx_pinv(a)` ((n, m) for an (m, n) matrix), `mlx_det(a)`,
    `call mlx_slogdet(a,sign,logabsdet)`, and `call mlx_svd(a,u,s,vt)` or `call mlx_svd(a,s)` (`a = u diag(s)
    vt` with `u` (m, m), `s` descending, `vt` (n, n): MLX's factors of the transpose are these, exchanged; a
    complex `vt` is the conjugate transpose of v);
  - the other triangle asked of MLX: `mlx_cholesky(a[,upper])` (the lower `l` with `a = l l^T`, or the upper
    `u` with `a = u^T u`; the other triangle of the result is exactly zero), `mlx_cholesky_inv(factor[,upper])`
    (the inverse of `a` from that factor), `mlx_tri_inv(a[,upper])` (the other triangle of `a` is not read),
    `mlx_eigvalsh(a[,uplo])` (ascending; `'L'` by default);
  - a transpose of the result, a view: `call mlx_eigh(a,w,v[,uplo])`, the eigenvectors as the columns of `v`
    (conjugated as well for a Hermitian matrix);
  - a transpose of the operand and of every matrix that comes back, all views:
    `call mlx_qr(a,q,r)` (`q` (m, k), `r` (k, n), k the smaller extent), `call mlx_lu(a,p,l,u)` (row i of `a`
    is row `p(i)` of `matmul(l,u)`; `l` unit lower, `u` upper), `call mlx_lu_factor(a,lu,pivots)` (LAPACK's
    packed factors; row i was exchanged with row `pivots(i)`, for i = 1, 2, ... in turn),
    `call mlx_eig(a,w,v)` and `mlx_eigvals(a)` (complex64 results, right eigenvectors as the columns of `v`,
    the same order of eigenvalues in both), `mlx_solve(a,b)` and `mlx_solve_triangular(a,b[,upper])`
    (`matmul(a,x) = b`; `b` is a vector, or right-hand sides as the columns of matrices, and `x` has its shape;
    `mlx_solve` needs the same batch dimensions on `a` and `b`, `mlx_solve_triangular` broadcasts them).
  - `p` and `pivots` are one-based int32 (binding rule for index results). Results that MLX returns as several
    arrays are subroutine arguments.
  - **Device.** MLX v0.32.4 implements all of these on the CPU only (the probe
    `scripts/probes/mlx_behaviour_probe.c` lists each refusal of the GPU stream). The wrappers submit them to
    the CPU's default stream whatever the default device; the transposes and the index shift stay on the
    default device, and MLX evaluates a graph that crosses the two (unified memory, no copy). float64 remains a
    CPU-device dtype: a float64 operand needs the CPU as the default device.
  - **Dtypes.** Real float32 and float64; `mlx_svd`, `mlx_eigh`, `mlx_eigvalsh`, `mlx_eig` and `mlx_eigvals`
    also take complex64. `mlx_eig` and `mlx_eigvals` return complex64 whatever the operand.
  - The tests (`linalg_matrix`) compare no factor: a backward error (`|a - factors|_F/|a|_F`), a residual
    (`|a x - 1|_F/(|a|_F |x|_F)`, `|a x - b|_F/(|a|_F |x|_F + |b|_F)`), the departure of a factor from
    orthogonal and the error of eigenvalues and singular values against a constructed spectrum are held to
    10 n epsilons of the result kind (n the larger extent); shapes, triangles, the permutation and the order
    are exact; a determinant is judged against real64 Gaussian elimination at 4 epsilons.
- **Norms.** `norm2(a[,dim][,keepdims])` and `norm2(a,dims[,keepdims])` are the Euclidean norm, as Fortran's
  (of magnitudes for complex arrays): of every element without `dim`, over at most two listed dimensions (the
  Frobenius norm of the matrices they span). `mlx_norm(a,ord[,dim][,keepdims])` and
  `mlx_norm(a,ord,dims[,keepdims])` take a real64 order: over one dimension the vector norm (the sum of
  `|a|**ord` to the power `1/ord`; the largest or smallest magnitude for plus or minus infinity; the count of
  nonzeros for 0), over two the matrix norm of the matrices whose rows run along `dims(1)` and columns along
  `dims(2)` (the largest column sum for 1, the smallest for -1, the row sums for plus and minus infinity, the
  largest and smallest singular value for 2 and -2). Without `dim` a rank-1 array is a vector and a rank-2
  array a matrix over dimensions (1, 2); a higher rank stops. `mlx_norm_matrix(a,ord[,dims][,keepdims])` takes
  `'fro'` or `'nuc'` (the sum of the singular values) over `dims`, dimensions 1 and 2 by default. The norms of
  singular values (2, -2, `'nuc'`) run on the CPU's default stream, the others on the default device.
- **Convolutions.** MLX's channels-last layouts read in Fortran order: the input is (C, W[, H[, D]], N), the
  kernels (C/groups, kW[, kH[, kD]], C_out), the result (C_out, W'[, H'[, D']], N).
  `mlx_conv1d`, `mlx_conv2d`, `mlx_conv3d`, `mlx_conv_general`, `mlx_conv_transpose1d`, `mlx_conv_transpose2d`
  and `mlx_conv_transpose3d` take `(input, weight[, spec])`, `spec` a `type(mlx_conv_spec)`: `stride`,
  `padding`, `dilation`, `output_padding`, `padding_hi`, `input_dilation` (integer lists, one value per spatial
  dimension **in Fortran's order, W first**; absent is the default, one value serves every dimension),
  `groups` (1) and `flip` (false). The wrapper reverses the lists for MLX.
  - A convolution is MLX's, a correlation: output element w' sums
    `input(:, (w'-1)*stride - padding + (k-1)*dilation + 1, n) * weight(:, k, o)` over k and the channels of the
    output channel's group, zeros outside the input. `mlx_conv_general` (one to three spatial dimensions, by
    the input's rank) also pads the far end by `padding_hi`, spreads the input by `input_dilation` and reverses
    the kernels with `flip` (a true convolution).
  - A transposed convolution adds `input(:, w, n) * weight(:, k, o)` to output element
    `(w-1)*stride - padding + (k-1)*dilation + 1`; the output's extent is
    `(W-1)*stride - 2*padding + dilation*(kW-1) + 1 + output_padding`. This holds for a padding up to
    `dilation*(kW-1)`: beyond it MLX v0.32.4 returns a shorter result (question 23 of
    `doc/collaboration/apple_questions.md`).
  - A field a function does not take stops (`padding_hi`, `input_dilation` and `flip` outside
    `mlx_conv_general`, `output_padding` outside the transposed ones), as does a list of another length and
    `groups` below 1. MLX takes groups in one and two spatial dimensions only.
  - MLX v0.32.4 computes a convolution in float32. A float64 one is computed in float32 on the CPU when
    neither the kernels nor the input are dilated (and, beyond one dimension, there is one group), and fails
    the evaluation with a status otherwise ("[Convolution::eval] got unsupported data type"): convert to
    float32. The tests (`conv`) judge float32 results against direct real64 sums, relative to `max(1,` the sum
    of magnitudes`)`, at 4 float32 epsilons on both devices.
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
- **Transforms over several dimensions.** `mlx_fftn(a[,dims,n,norm])` and `mlx_ifftn(a[,dims,n,norm])`
  transform the listed dimensions, every dimension when `dims` is absent, and treat the others as batches.
  `n` gives one length per transformed dimension, paired with `dims` in its order (with dimensions 1 to rank
  when `dims` is absent); a length pads with zeros or truncates, as in one dimension. Over two dimensions
  `mlx_fftn` gives `mlx_fft2`'s result bit for bit.
- **Real transforms over several dimensions: the half-size dimension is the first listed.**
  `mlx_rfftn(a[,dims,n,norm])` and `mlx_rfft2(a,dims[,n,norm])` keep the `n(1)/2+1` non-negative frequencies
  along `dims(1)` (dimension 1 when `dims` is absent) and every frequency along the other transformed
  dimensions: a real (n1, n2, n3) array has the complex (n1/2+1, n2, n3) spectrum, as a real-to-complex
  transform has in Fortran (FFTW's Fortran interface halves the first dimension, C's and NumPy's the last
  axis). Dimension 1 is MLX's last axis, so `mlx_rfftn(a)` is MLX's own default; for other choices the
  wrapper passes `dims(1)` last, where MLX halves. `mlx_irfftn(a[,dims,n,norm])` and
  `mlx_irfft2(a,dims[,n,norm])` are the inverses: `n` gives the real lengths, by default the extents and
  `2*(extent-1)` along `dims(1)`, so an odd length there needs `n`, as for `mlx_irfft`. An inverse real
  transform takes the half spectrum of a real array: the imaginary parts of the zero and the Nyquist
  frequency along the half-size dimension do not enter, and a length that cuts or pads one of the *other*
  dimensions makes an input that is no real array's spectrum (not tested, and not defined by MLX).
- `mlx_fftshift(a[,dims])` moves the zero frequency to the centre of each listed dimension (every dimension
  by default), element `extent/2 + 1`: Fortran's `cshift(a, -(extent/2), dim)`. `mlx_ifftshift(a[,dims])` is
  `cshift(a, extent/2, dim)` and undoes it; the two differ along a dimension of odd extent.
- `mlx_fftfreq(n[,d])` is the rank-1 float32 array of the n frequencies of a transform, in the transform's
  order, (0, 1, ..., -2, -1)/(n d) with the negative frequencies last and `d` the sample spacing (real64,
  1 by default); `mlx_rfftfreq(n[,d])` is the n/2+1 non-negative ones of a real transform.
  `mlx_fftshift(mlx_fftfreq(n))` ascends, with zero at element n/2+1.
- The tests of these transforms (`fft_nd` of `unit_fft`) judge a result by its largest error relative to
  `max(1, the largest |reference| of the result)` against a direct real64 DFT: an element near a zero of a
  spectrum carries the rounding of the whole transform. The frozen tolerances are 4 float32 epsilons, and
  4.18 and 4.02 for `mlx_irfftn` and `mlx_irfft2`.


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

## 12. Custom Metal kernels

`k = mlx_metal_kernel(spec)` (or `call k%new(spec)`) builds a kernel from the record `mlx_metal_kernel_spec`,
and `call k%apply(inputs, outputs[, status])` adds one application of it to the graph. A kernel is for a
measured bottleneck that ordinary or compiled operations cannot handle. It runs on the GPU only, so the
graph form of the same computation stays as the CPU path and as the reference.

- **The spec** is a record of plain components, filled by assignment:

  | component | meaning | default |
  | --- | --- | --- |
  | `name` | the kernel's name (MLX builds the Metal function's name from it) | required |
  | `source` | the body of the Metal function; MLX writes its signature | required |
  | `header` | declarations placed before the function (helper functions) | none |
  | `input_names(:)`, `output_names(:)` | the names the buffers take in the source, in the order of `inputs` and `outputs` | no input; at least one output |
  | `grid(3)`, `threadgroup(3)` | the threads launched and their grouping, as Metal's (x, y, z); they are not array shapes and are not reversed | `[1, 1, 1]` each |
  | `output_shapes(:)` | the outputs' Fortran shapes, one after another | required |
  | `output_ranks(:)` | how many extents of `output_shapes` each output takes (0 for a rank-0 output) | the outputs share the extents equally |
  | `output_dtypes(:)` | one `MLX_DTYPES` member per output | float32 |
  | `template_dtype_names(:)` with `template_dtypes(:)`, `template_int_names(:)` with `template_ints(:)`, `template_bool_names(:)` with `template_bools(:)` | template parameters of the Metal function: a type name, an `int` or a `bool` per name | none |
  | `init_value` | when set, every output is filled with it before the kernel runs | not set: the outputs start undefined |
  | `ensure_row_contiguous` | MLX copies a strided input (a transpose, a section) first, so the source sees the array's elements in array element order | `.true.` |
  | `atomic_outputs` | the outputs are `atomic<T>` buffers, for threads that add to the same element | `.false.` |
  | `verbose` | MLX prints the Metal source it generates at each application | `.false.` |

  `new` validates the spec once and stops on an invalid one (no name, no source, no output, shapes that do
  not match the outputs, a dtype outside `MLX_DTYPES`, a grid or threadgroup below 1, a template name without
  its value). The launch configuration belongs to the kernel object: another grid or output shape is another
  kernel, built from the edited spec. That is cheap, because MLX compiles a generated source once per process:
  on the M5 Ultra the first evaluation of a new source took 60 ms, and building, applying and evaluating a
  second kernel object with the same source and another grid took 0.2 ms.
- **What MLX generates.** For an input named `a` the source gets `const device T* a` with T the input's dtype
  (`float`, `int`, `complex64_t` with members `real` and `imag`, ...); also `a_shape`, `a_strides` and `a_ndim`
  when the source names them. An input of fewer than 8 elements is passed in Metal's `constant` address space,
  and a rank-0 input as a reference: `scale`, not `scale[0]`. An output named `out` is `device T* out`, or
  `device atomic<T>* out` under `atomic_outputs`, rank 0 included (`out[0]`). The Metal attributes the source
  names (`thread_position_in_grid`, `threads_per_grid`, `threads_per_simdgroup`, ...) become arguments, and
  MLX's kernel utilities (`elem_to_loc`, ...) are in scope.
- **The source sees MLX's layout: row-major, 0-based, the shape reversed.** A Fortran array `a(n1, n2)` is
  MLX's `[n2, n1]`: in the source `a_shape[0]` is n2, `a_shape[1]` is n1, and element `a(i, j)` is
  `a[(j-1)*n1 + (i-1)]`. In general element (i1, ..., ir) is at `(i1-1) + n1*((i2-1) + n2*(...))`, its
  position in Fortran's array element order less one, and `a_shape[k]` is the extent of dimension r - k. One
  thread per element, `elem = thread_position_in_grid.x` with `grid = [size, 1, 1]`, therefore visits the
  array in array element order; the first subscript is `elem % a_shape[r-1] + 1`. With `grid = [n1, n2, 1]`,
  `thread_position_in_grid.x` is i - 1 and `.y` is j - 1. Index values that a Fortran program passes in an
  array are whatever it stored: the tests pass 1-based bins and the source subtracts 1. A worked example, the
  kernel that adds to each element of a rank-2 array the number of its column:

  ```fortran
  spec%name = 'add_column'
  spec%input_names = ['inp']
  spec%output_names = ['out']
  spec%source = 'uint elem = thread_position_in_grid.x;'//new_line('a')// &
                'out[elem] = inp[elem] + float(elem / inp_shape[1] + 1);'
  spec%grid = [size(x), 1, 1]
  spec%threadgroup = [64, 1, 1]
  spec%output_shapes = shape(x)
  k = mlx_metal_kernel(spec)
  call k%apply([a], outputs)          ! outputs(1) has x's shape and holds x(i, j) + j
  ```

  With `ensure_row_contiguous = .false.` a strided input reaches the source as its buffer, in storage order:
  the source then goes through `elem_to_loc(elem, a_shape, a_strides, a_ndim)`.
- **Errors.** `apply` is a checked procedure. It returns a status, with `outputs` unallocated and MLX usable,
  when the default device is the CPU ("[metal_kernel] Only supports the GPU"), when the number of inputs is
  not the number of input names, when an input is empty or stale ("mlx_metal_kernel apply: an input array is
  empty or stale"), and when an output is float64. The source
  is compiled at the first evaluation of a result, so a source that does not compile, and a threadgroup above
  the device's limit (1,024 threads on the M5 Ultra, checked before the grid clips it), fail `mlx_eval`,
  `mlx_to` or `mlx_view` with a status; `mlx_last_error()` then holds the Metal compiler's message with the
  source line. An empty or stale kernel stops in `apply`, as an empty array stops an operation.
- **Lifetime.** A kernel is a counted handle like `mlx_function`: assignment shares it, `kill` is idempotent,
  finalization releases it, and it counts as one object in `mlx_live_count()`. A graph keeps what it needs of
  an applied kernel, so the kernel object may be killed before its outputs are evaluated. Empty kernels may be
  copied and killed anywhere; a live one only from the submitting thread. The unsupported forms of section 3
  apply.
- **In a compiled function.** A callback may build and apply a kernel and use the result in further
  operations; `mlx_compile` then traces the kernel as one node. `apply` takes `status=`, which the callback
  returns; building a kernel from an invalid spec stops, as an operator does on a program error, so a callback
  builds only from a spec known to be valid. The grid and the output shapes are those of the trace: a
  compiled function that holds a kernel is for the shapes it was traced with; MLX refuses to compile one
  shapeless ("CustomKernel cannot infer output shapes", returned through the status; MLX 0.32.4).
- **Math mode.** Kernels built through mlx-c run in MLX's default safe mode (question 21 of the Apple
  questions): a compensated sum is honoured; `metal::precise::exp` is within one unit of the correctly
  rounded value and plain `exp` 62 units from it (measured with MLX 0.32.4). A source that needs accuracy
  calls the `precise` functions.
- The gates: `unit_fast` (exact results on the GPU for the layout, a two-dimensional grid, two inputs and two
  outputs, templates and a header, a strided input with and without the copy, atomic int32 outputs with
  colliding updates, complex64 and rank-0 inputs, a kernel without inputs, a kernel inside a compiled
  function; the refusals above through `status`; the refusal on the CPU device), and two guards of
  `object_contracts` (a spec without outputs, an empty kernel applied). Not tested in `unit_fast`: the other stops
  of `new`, a stale kernel, an output above rank 2 (rank 3 worked in a probe with MLX 0.32.4), a template dtype
  other than float32.
- **Measured by the toys** (MLX 0.32.4, M5 Ultra). A complex64 output of rank 2 (`complex64_t`, written by
  members) holds its values bit for bit; the toy projector's fused gather writes its bank so (`unit_kernels`,
  suite `projector`). A float32 output under `atomic_outputs` adds colliding `atomic_fetch_add_explicit` updates
  correctly (one million additions of 0.1 to one element within 3.5e-6 of the exact sum) but not in a repeatable
  order: an insertion of 2.84e8 such deposits gives different bits in up to 49 % of its 2.3e6 elements from run to
  run (`bench_insert_probe`). A `threadgroup` array declared in the body, with `threadgroup_barrier`, builds and
  gives correct results, though MLX's documentation does not name it (question 26 of the Apple questions).
