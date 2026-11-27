# The mlxf API reference

Generated from the source by `scripts/generate_api_reference.py`, never edited; `scripts/check_tree.sh` fails when it is not current. One entry per public name of `mlxf`, in the order of `src/core/mlxf.f90`: each specific with its dummies as the source declares them (`[x]` is optional, passed by keyword), the comment above it in the source, and the section of the binding policy that holds the contract (what stops, what returns a status, kinds and shapes). 317 names.

## `mlxf_version_string`

*Module* `mlxf_version`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlxf_version_string()
        result         character(len=:), allocatable :: v
        ! the mlx-fortran release
```

## `mlxf_build_description`

*Module* `mlxf_version`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlxf_build_description()
        result         character(len=:), allocatable :: d
        ! the release, build type and Fortran compiler, and the mlx-c the library was configured with
```

## `mlx_runtime_version`

*Module* `mlxf_version`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlx_runtime_version()
        result         character(len=:), allocatable :: v
        ! the version of the MLX library loaded at run time
```

## `mlxf_runtime_description`

*Module* `mlxf_version`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlxf_runtime_description()
        result         character(len=:), allocatable :: d
        ! what decides MLX's arithmetic here: its version, the default device, the GPU's architecture and MLX_ENABLE_TF32 (MLX's own variable: unset or 1 lets GPUs with matrix units multiply float32 at reduced precision; the library never changes it)
```

## `MLXF_HARD_ERROR_STATUS`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
MLXF_HARD_ERROR_STATUS (a named constant): the exit status of every stop the library makes, so that a test can tell it from a runtime failure
    integer, parameter :: MLXF_HARD_ERROR_STATUS = 86
```

## `MLX_DEVICES`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
MLX_DEVICES (a named constant)
    type(mlx_device_codes), parameter :: MLX_DEVICES = mlx_device_codes()
    codes:
        component  integer :: cpu = int(MLXC_CPU)
        component  integer :: gpu = int(MLXC_GPU)
```

## `MLX_DTYPES`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
MLX_DTYPES (a named constant)
    type(mlx_dtype_codes), parameter :: MLX_DTYPES = mlx_dtype_codes()
    codes:
        component  integer :: bool = int(MLXC_BOOL)
        component  integer :: int32 = int(MLXC_INT32)
        component  integer :: int64 = int(MLXC_INT64)
        component  integer :: float32 = int(MLXC_FLOAT32)
        component  integer :: float64 = int(MLXC_FLOAT64)
        component  integer :: complex64 = int(MLXC_COMPLEX64)
        component  integer :: int8 = int(MLXC_INT8)
        component  integer :: int16 = int(MLXC_INT16)
        component  integer :: uint8 = int(MLXC_UINT8)
        component  integer :: uint16 = int(MLXC_UINT16)
        component  integer :: uint32 = int(MLXC_UINT32)
        component  integer :: uint64 = int(MLXC_UINT64)
        component  integer :: float16 = int(MLXC_FLOAT16)
        component  integer :: bfloat16 = int(MLXC_BFLOAT16)
```

## `mlx_last_error`

*Module* `mlxf_error`; *contract:* [6. Errors](policies/binding_contract_policy.md#6-errors)

```text
    function mlx_last_error()
        result         character(len=:), allocatable :: msg
        ! the message of the last error MLX or the library reported (empty if none)
```

## `mlx_live_count`

*Module* `mlxf_registry`; *contract:* [3. Lifetime](policies/binding_contract_policy.md#3-lifetime)

```text
    function mlx_live_count()
        result         integer
        ! the number of live MLX objects the library holds: equal before and after a loop that leaks nothing
```

## `mlx_metal_is_available`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlx_metal_is_available()
        result         logical
        ! whether MLX was built with its Metal backend; true on a Metal build also when no GPU opens in this session (mlx_device_count says whether one does), false on a CPU-only build, which allocates on the CPU device
```

## `mlx_device_count`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlx_device_count(device_type)
        device_type    integer, intent(in) :: device_type
        result         integer
        ! the number of devices of a type (MLX_DEVICES%cpu or %gpu) MLX can open here
```

## `mlx_default_device`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlx_default_device()
        result         integer
        ! the type of MLX's default device: MLX_DEVICES%cpu or %gpu
```

## `mlx_set_default_device`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    subroutine mlx_set_default_device(device_type, [status])
        device_type    integer, intent(in) :: device_type
        status         integer, optional, intent(out) :: status
        ! makes a device type (MLX_DEVICES%cpu or %gpu) MLX's default for the operations that follow
```

## `mlx_device_info_size`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlx_device_info_size(device_type, key, [status])
        device_type    integer, intent(in) :: device_type
        key            character(len=*), intent(in) :: key
        status         integer, optional, intent(out) :: status
        result         integer(int64) :: n
        ! a size MLX reports for a device (max_buffer_length, memory_size, ...); -1 with status 0 when the device or the key is absent. A failure inside MLX is an error, never a -1 alone: the status, or a stop without one
```

## `mlx_device_info_string`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlx_device_info_string(device_type, key, [status])
        device_type    integer, intent(in) :: device_type
        key            character(len=*), intent(in) :: key
        status         integer, optional, intent(out) :: status
        result         character(len=:), allocatable :: s
        ! a string MLX reports for a device (device_name, architecture, ...); empty with status 0 when the device or the key is absent. A failure inside MLX is an error, never an empty string alone: the status, or a stop
```

## `mlx_cuda_is_available`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlx_cuda_is_available()
        result         logical
        ! whether MLX was built with its CUDA backend; true on a CUDA build also when no GPU opens in this session (none present, or none visible through CUDA_VISIBLE_DEVICES: mlx_device_count says whether one does)
```

## `mlx_active_memory`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    function mlx_active_memory()
        result         integer(int64) :: n
        ! bytes held by live arrays
```

## `mlx_peak_memory`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    function mlx_peak_memory()
        result         integer(int64) :: n
        ! the largest active memory since the start or the last reset
```

## `mlx_reset_peak_memory`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    subroutine mlx_reset_peak_memory()
```

## `mlx_cache_memory`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    function mlx_cache_memory()
        result         integer(int64) :: n
        ! bytes MLX keeps cached for reuse
```

## `mlx_clear_cache`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    subroutine mlx_clear_cache()
```

## `mlx_set_memory_limit`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    subroutine mlx_set_memory_limit(bytes, [previous], [status])
        bytes          integer(int64), intent(in) :: bytes
        previous       integer(int64), optional, intent(out) :: previous
        status         integer, optional, intent(out) :: status
        ! the memory limit evaluation keeps to by waiting and releasing cached buffers; returns the previous limit
```

## `mlx_set_cache_limit`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    subroutine mlx_set_cache_limit(bytes, [previous])
        bytes          integer(int64), intent(in) :: bytes
        previous       integer(int64), optional, intent(out) :: previous
        ! the cache limit; returns the previous limit
```

## `mlx_memory_limit`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    function mlx_memory_limit()
        result         integer(int64) :: n
        ! the memory limit in force
```

## `mlx_set_wired_limit`

*Module* `mlxf_memory`; *contract:* [8. Evaluation and memory](policies/binding_contract_policy.md#8-evaluation-and-memory)

```text
    subroutine mlx_set_wired_limit(bytes, [previous], [status])
        bytes          integer(int64), intent(in) :: bytes
        previous       integer(int64), optional, intent(out) :: previous
        status         integer, optional, intent(out) :: status
        ! the bytes of memory the GPU may keep wired (0, MLX's default: none is held); returns the previous limit. A limit above what the system allows is refused with a status
```

## `mlx_buffer_size`

*Module* `mlxf_array`; *contract:* [3. Lifetime](policies/binding_contract_policy.md#3-lifetime)

```text
    function mlx_buffer_size(arrays, [status])
        arrays         type(mlx_array), intent(in) :: arrays(:)
        status         integer, optional, intent(out) :: status
        result         integer(int64) :: n
```

## `mlx_device_is_available`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    function mlx_device_is_available(device_type)
        device_type    integer, intent(in) :: device_type
        result         logical
        ! whether MLX can use the first device of a type (MLX_DEVICES%cpu or %gpu) in this session
```

## `mlx_metal_start_capture`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    subroutine mlx_metal_start_capture(path, [status])
        path           character(len=*), intent(in) :: path
        status         integer, optional, intent(out) :: status
        ! starts a Metal capture of the GPU's work into the trace file path (for Xcode); Metal refuses it unless the process was started with MTL_CAPTURE_ENABLED=1, and the refusal is a status
```

## `mlx_metal_stop_capture`

*Module* `mlxf_device`; *contract:* [7. Devices, threads, precision](policies/binding_contract_policy.md#7-devices-threads-precision)

```text
    subroutine mlx_metal_stop_capture([status])
        status         integer, optional, intent(out) :: status
        ! ends the Metal capture
```

## `mlx_stream`

*Module* `mlxf_stream`; *contract:* [16. Streams, device availability and Metal capture](policies/binding_contract_policy.md#16-streams-device-availability-and-metal-capture)

```text
mlx_stream (a derived type)
    %kill, bound to stream_kill:
        subroutine kill(self)
            self           class(mlx_stream), intent(inout) :: self
    assignment(=), for these operand pairs:
        class(mlx_stream), intent(inout), class(mlx_stream)
```

## `mlx_new_stream`

*Module* `mlxf_stream`; *contract:* [16. Streams, device availability and Metal capture](policies/binding_contract_policy.md#16-streams-device-availability-and-metal-capture)

```text
    function mlx_new_stream(device_type)
        device_type    integer, intent(in) :: device_type
        result         type(mlx_stream) :: s
        ! a new stream on a device type, MLX_DEVICES%cpu or %gpu: a queue of its own
```

## `mlx_default_stream`

*Module* `mlxf_stream`; *contract:* [16. Streams, device availability and Metal capture](policies/binding_contract_policy.md#16-streams-device-availability-and-metal-capture)

```text
    function mlx_default_stream(device_type)
        device_type    integer, intent(in) :: device_type
        result         type(mlx_stream) :: s
        ! a device type's default stream as it is now: the one operations on that device run on
```

## `mlx_set_default_stream`

*Module* `mlxf_stream`; *contract:* [16. Streams, device availability and Metal capture](policies/binding_contract_policy.md#16-streams-device-availability-and-metal-capture)

```text
    subroutine mlx_set_default_stream(stream)
        stream         type(mlx_stream), intent(in) :: stream
        ! makes stream the default of its device: the operations built on that device from now on run on it
```

## `mlx_save`

*Module* `mlxf_io`; *contract:* [17. Arrays in files, and the text of a graph](policies/binding_contract_policy.md#17-arrays-in-files-and-the-text-of-a-graph)

```text
    subroutine mlx_save(file, a, [status])
        file           character(len=*), intent(in) :: file
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
        ! writes a, evaluated, to file in NumPy's .npy format; '.npy' is added to a name that does not end with it. The file is replaced only by a complete write (mlxf_save_begin)
```

## `mlx_load`

*Module* `mlxf_io`; *contract:* [17. Arrays in files, and the text of a graph](policies/binding_contract_policy.md#17-arrays-in-files-and-the-text-of-a-graph)

```text
    function mlx_load(file, [status])
        file           character(len=*), intent(in) :: file
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: a
        ! the array of a .npy file, whose name is given whole; with status, a failure returns an empty array. The data are read when the array is evaluated: the file must stay as it is until then
```

## `mlx_save_safetensors`

*Module* `mlxf_io`; *contract:* [17. Arrays in files, and the text of a graph](policies/binding_contract_policy.md#17-arrays-in-files-and-the-text-of-a-graph)

```text
    subroutine mlx_save_safetensors(file, names, arrays, [metadata], [status])
        file           character(len=*), intent(in) :: file
        names          character(len=*), intent(in) :: names(:)
        arrays         type(mlx_array), intent(in) :: arrays(:)
        metadata       character(len=*), optional, intent(in) :: metadata(:, :)
        status         integer, optional, intent(out) :: status
        ! writes arrays under their names to a safetensors file, with metadata, pairs of strings (1, i) and (2, i), when given. Trailing blanks of names and strings are not written; '.safetensors' is added to a name that does not end with it. float64 is refused before anything is written; the file is replaced only by a complete write
```

## `mlx_load_safetensors`

*Module* `mlxf_io`; *contract:* [17. Arrays in files, and the text of a graph](policies/binding_contract_policy.md#17-arrays-in-files-and-the-text-of-a-graph)

```text
    subroutine mlx_load_safetensors(file, names, arrays, [metadata], [status])
        file           character(len=*), intent(in) :: file
        names          character(len=:), allocatable, intent(out) :: names(:)
        arrays         type(mlx_array), allocatable, intent(out) :: arrays(:)
        metadata       character(len=:), allocatable, optional, intent(out) :: metadata(:, :)
        status         integer, optional, intent(out) :: status
        ! the arrays of a safetensors file and their names, sorted by name, and its metadata as pairs of strings (1, i) and (2, i), sorted by the first; with status, a failure returns with the lists unallocated
```

## `mlx_save_gguf`

*Module* `mlxf_io`; *contract:* [17. Arrays in files, and the text of a graph](policies/binding_contract_policy.md#17-arrays-in-files-and-the-text-of-a-graph)

```text
    subroutine mlx_save_gguf(file, names, arrays, [status])
        file           character(len=*), intent(in) :: file
        names          character(len=*), intent(in) :: names(:)
        arrays         type(mlx_array), intent(in) :: arrays(:)
        status         integer, optional, intent(out) :: status
        ! writes arrays under their names to a GGUF file, without metadata; '.gguf' is added to a name that does not end with it. A kind GGUF lacks in MLX (any but int8, int16, int32, float16 and float32) is refused before anything is written; the file is replaced only by a complete write
```

## `mlx_load_gguf`

*Module* `mlxf_io`; *contract:* [17. Arrays in files, and the text of a graph](policies/binding_contract_policy.md#17-arrays-in-files-and-the-text-of-a-graph)

```text
    subroutine mlx_load_gguf(file, names, arrays, [status])
        file           character(len=*), intent(in) :: file
        names          character(len=:), allocatable, intent(out) :: names(:)
        arrays         type(mlx_array), allocatable, intent(out) :: arrays(:)
        status         integer, optional, intent(out) :: status
        ! the arrays of a GGUF file and their names, sorted by name; its metadata are not read
```

## `mlx_print_graph`

*Module* `mlxf_io`; *contract:* [17. Arrays in files, and the text of a graph](policies/binding_contract_policy.md#17-arrays-in-files-and-the-text-of-a-graph)

```text
    subroutine mlx_print_graph(arrays, [file], [status])
        arrays         type(mlx_array), intent(in) :: arrays(:)
        file           character(len=*), optional, intent(in) :: file
        status         integer, optional, intent(out) :: status
        ! writes the graph that computes arrays as text, one line per operation, to file, or to the standard output
```

## `mlx_export_to_dot`

*Module* `mlxf_io`; *contract:* [17. Arrays in files, and the text of a graph](policies/binding_contract_policy.md#17-arrays-in-files-and-the-text-of-a-graph)

```text
    subroutine mlx_export_to_dot(file, arrays, [status])
        file           character(len=*), intent(in) :: file
        arrays         type(mlx_array), intent(in) :: arrays(:)
        status         integer, optional, intent(out) :: status
        ! writes the graph that computes arrays to file in Graphviz's dot language
```

## `mlx_group`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
mlx_group (a derived type)
    %rank, bound to group_rank:
        function rank(self)
            self           class(mlx_group), intent(in) :: self
            result         integer
    %size, bound to group_size:
        function size(self)
            self           class(mlx_group), intent(in) :: self
            result         integer
    %split, bound to group_split:
        function split(self, color, [key], [status])
            self           class(mlx_group), intent(in) :: self
            color          integer, intent(in) :: color
            key            integer, optional, intent(in) :: key
            status         integer, optional, intent(out) :: status
            result         type(mlx_group) :: g
    %kill, bound to group_kill:
        subroutine kill(self)
            self           class(mlx_group), intent(inout) :: self
    assignment(=), for these operand pairs:
        class(mlx_group), intent(inout), class(mlx_group)
```

## `mlx_distributed_init`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_distributed_init([backend], [strict], [status])
        backend        character(len=*), optional, intent(in) :: backend
        strict         logical, optional, intent(in) :: strict
        status         integer, optional, intent(out) :: status
        result         type(mlx_group) :: g
        ! the group of the processes this one was launched with, through backend ('any', the default, 'ring', 'jaccl', 'mpi', 'nccl'). Without strict, a process no backend launched gets a group of one; with it, that is a failure. With status, a failure returns an empty group
```

## `mlx_distributed_is_available`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_distributed_is_available([backend])
        backend        character(len=*), optional, intent(in) :: backend
        result         logical
        ! whether MLX has a distributed backend ('any', the default: whether it has one at all)
```

## `mlx_all_sum`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_all_sum(x, [group], [status])
        x              type(mlx_array), intent(in) :: x
        group          type(mlx_group), optional, intent(in) :: group
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: r
        ! the sum of x over the processes of the group (MLX's default group when none is given), on each of them
```

## `mlx_all_max`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_all_max(x, [group], [status])
        x              type(mlx_array), intent(in) :: x
        group          type(mlx_group), optional, intent(in) :: group
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: r
        ! the elementwise maximum of x over the processes of the group
```

## `mlx_all_min`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_all_min(x, [group], [status])
        x              type(mlx_array), intent(in) :: x
        group          type(mlx_group), optional, intent(in) :: group
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: r
        ! the elementwise minimum of x over the processes of the group
```

## `mlx_all_gather`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_all_gather(x, [group], [status])
        x              type(mlx_array), intent(in) :: x
        group          type(mlx_group), optional, intent(in) :: group
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: r
        ! the x of every process joined along the last dimension (MLX's first axis), in the order of the ranks
```

## `mlx_sum_scatter`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_sum_scatter(x, [group], [status])
        x              type(mlx_array), intent(in) :: x
        group          type(mlx_group), optional, intent(in) :: group
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: r
        ! the sum of x over the processes, of which each keeps its own share along the last dimension
```

## `mlx_send`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_send(x, dst, [group], [status])
        x              type(mlx_array), intent(in) :: x
        dst            integer, intent(in) :: dst
        group          type(mlx_group), optional, intent(in) :: group
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: r
        ! x, sent to the process of rank dst (one-based) when the result is evaluated; the result is x
```

## `mlx_recv`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_recv(shape, dtype, src, [group], [status])
        shape          integer, intent(in) :: shape(:)
        dtype          integer, intent(in) :: dtype
        src            integer, intent(in) :: src
        group          type(mlx_group), optional, intent(in) :: group
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: r
        ! an array of the Fortran shape and the dtype given, received from the process of rank src (one-based)
```

## `mlx_recv_like`

*Module* `mlxf_distributed`; *contract:* [18. Distributed computing](policies/binding_contract_policy.md#18-distributed-computing)

```text
    function mlx_recv_like(x, src, [group], [status])
        x              type(mlx_array), intent(in) :: x
        src            integer, intent(in) :: src
        group          type(mlx_group), optional, intent(in) :: group
        status         integer, optional, intent(out) :: status
        result         type(mlx_array) :: r
        ! an array of x's shape and dtype, received from the process of rank src (one-based)
```

## `mlx_array`

*Module* `mlxf_array`; *contract:* [3. Lifetime](policies/binding_contract_policy.md#3-lifetime)

```text
mlx_array (a derived type)
    %shape, bound to array_shape:
        function shape(self)
            self           class(mlx_array), intent(in) :: self
            result         integer, allocatable :: s(:)
    %ndim, bound to array_ndim:
        function ndim(self)
            self           class(mlx_array), intent(in) :: self
            result         integer
    %size, bound to array_size:
        function size(self)
            self           class(mlx_array), intent(in) :: self
            result         integer(int64)
    %kind, bound to array_kind:
        function kind(self)
            self           class(mlx_array), intent(in) :: self
            result         integer
    %nbytes, bound to array_nbytes:
        function nbytes(self)
            self           class(mlx_array), intent(in) :: self
            result         integer(int64)
    %itemsize, bound to array_itemsize:
        function itemsize(self)
            self           class(mlx_array), intent(in) :: self
            result         integer
    %kill, bound to kill_array:
        subroutine kill(self)
            self           class(mlx_array), intent(inout) :: self
    assignment(=), for these operand pairs:
        class(mlx_array), intent(inout), class(mlx_array)
    operator(+), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
        class(mlx_array)
    operator(-), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
        class(mlx_array)
    operator(*), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(/), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(**), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(<), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(<=), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(>), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(>=), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(==), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(/=), for these operand pairs:
        class(mlx_array), class(mlx_array)
        class(mlx_array), real(real32)
        real(real32), class(mlx_array)
        class(mlx_array), real(real64)
        real(real64), class(mlx_array)
        class(mlx_array), integer
        integer, class(mlx_array)
    operator(.and.), for these operand pairs:
        class(mlx_array), class(mlx_array)
    operator(.or.), for these operand pairs:
        class(mlx_array), class(mlx_array)
    operator(.eqv.), for these operand pairs:
        class(mlx_array), class(mlx_array)
    operator(.neqv.), for these operand pairs:
        class(mlx_array), class(mlx_array)
    operator(.not. ), for these operand pairs:
        class(mlx_array)
```

## `mlx_from`

*Module* `mlxf_transfer`; *contract:* [4. Data in and out](policies/binding_contract_policy.md#4-data-in-and-out)

```text
generic mlx_from
    function mlx_from(x)
        x              real(real32), target, contiguous, intent(in) :: x(..)
        result         type(mlx_array) :: a
    function mlx_from(x)
        x              real(real64), target, contiguous, intent(in) :: x(..)
        result         type(mlx_array) :: a
    function mlx_from(x)
        x              complex(real32), target, contiguous, intent(in) :: x(..)
        result         type(mlx_array) :: a
    function mlx_from(x)
        x              integer(int32), target, contiguous, intent(in) :: x(..)
        result         type(mlx_array) :: a
    function mlx_from(x)
        x              integer(int8), target, contiguous, intent(in) :: x(..)
        result         type(mlx_array) :: a
    function mlx_from(x)
        x              integer(int16), target, contiguous, intent(in) :: x(..)
        result         type(mlx_array) :: a
    function mlx_from(x)
        x              integer(int64), target, contiguous, intent(in) :: x(..)
        result         type(mlx_array) :: a
    function mlx_from(x)
        x              logical(c_bool), target, contiguous, intent(in) :: x(..)
        result         type(mlx_array) :: a
```

## `mlx_to`

*Module* `mlxf_transfer`; *contract:* [4. Data in and out](policies/binding_contract_policy.md#4-data-in-and-out)

```text
generic mlx_to
    subroutine mlx_to(y, a, [status])
        y              real(real32), target, contiguous, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to(y, a, [status])
        y              real(real64), target, contiguous, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to(y, a, [status])
        y              complex(real32), target, contiguous, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to(y, a, [status])
        y              integer(int32), target, contiguous, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to(y, a, [status])
        y              integer(int8), target, contiguous, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to(y, a, [status])
        y              integer(int16), target, contiguous, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to(y, a, [status])
        y              integer(int64), target, contiguous, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to(y, a, [status])
        y              logical(c_bool), target, contiguous, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
```

## `mlx_to_alloc`

*Module* `mlxf_transfer`; *contract:* [4. Data in and out](policies/binding_contract_policy.md#4-data-in-and-out)

```text
generic mlx_to_alloc
    subroutine mlx_to_alloc(y, a, [status])
        y              real(real32), allocatable, target, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to_alloc(y, a, [status])
        y              real(real64), allocatable, target, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to_alloc(y, a, [status])
        y              complex(real32), allocatable, target, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to_alloc(y, a, [status])
        y              integer(int32), allocatable, target, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to_alloc(y, a, [status])
        y              integer(int8), allocatable, target, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to_alloc(y, a, [status])
        y              integer(int16), allocatable, target, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to_alloc(y, a, [status])
        y              integer(int64), allocatable, target, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_to_alloc(y, a, [status])
        y              logical(c_bool), allocatable, target, intent(inout) :: y(..)
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
```

## `mlx_item`

*Module* `mlxf_transfer`; *contract:* [4. Data in and out](policies/binding_contract_policy.md#4-data-in-and-out)

```text
generic mlx_item
    subroutine mlx_item(a, value, [status])
        a              type(mlx_array), intent(in) :: a
        value          real(real32), intent(out) :: value
        status         integer, optional, intent(out) :: status
    subroutine mlx_item(a, value, [status])
        a              type(mlx_array), intent(in) :: a
        value          real(real64), intent(out) :: value
        status         integer, optional, intent(out) :: status
    subroutine mlx_item(a, value, [status])
        a              type(mlx_array), intent(in) :: a
        value          complex(real32), intent(out) :: value
        status         integer, optional, intent(out) :: status
    subroutine mlx_item(a, value, [status])
        a              type(mlx_array), intent(in) :: a
        value          integer(int8), intent(out) :: value
        status         integer, optional, intent(out) :: status
    subroutine mlx_item(a, value, [status])
        a              type(mlx_array), intent(in) :: a
        value          integer(int16), intent(out) :: value
        status         integer, optional, intent(out) :: status
    subroutine mlx_item(a, value, [status])
        a              type(mlx_array), intent(in) :: a
        value          integer(int32), intent(out) :: value
        status         integer, optional, intent(out) :: status
    subroutine mlx_item(a, value, [status])
        a              type(mlx_array), intent(in) :: a
        value          integer(int64), intent(out) :: value
        status         integer, optional, intent(out) :: status
    subroutine mlx_item(a, value, [status])
        a              type(mlx_array), intent(in) :: a
        value          logical(c_bool), intent(out) :: value
        status         integer, optional, intent(out) :: status
```

## `mlx_view`

*Module* `mlxf_transfer`; *contract:* [4. Data in and out](policies/binding_contract_policy.md#4-data-in-and-out)

```text
generic mlx_view
    subroutine mlx_view(a, p, [status])
        a              type(mlx_array), intent(in) :: a
        p              real(real32), pointer, intent(inout) :: p(..)
        status         integer, optional, intent(out) :: status
    subroutine mlx_view(a, p, [status])
        a              type(mlx_array), intent(in) :: a
        p              real(real64), pointer, intent(inout) :: p(..)
        status         integer, optional, intent(out) :: status
    subroutine mlx_view(a, p, [status])
        a              type(mlx_array), intent(in) :: a
        p              complex(real32), pointer, intent(inout) :: p(..)
        status         integer, optional, intent(out) :: status
    subroutine mlx_view(a, p, [status])
        a              type(mlx_array), intent(in) :: a
        p              integer(int32), pointer, intent(inout) :: p(..)
        status         integer, optional, intent(out) :: status
    subroutine mlx_view(a, p, [status])
        a              type(mlx_array), intent(in) :: a
        p              integer(int8), pointer, intent(inout) :: p(..)
        status         integer, optional, intent(out) :: status
    subroutine mlx_view(a, p, [status])
        a              type(mlx_array), intent(in) :: a
        p              integer(int16), pointer, intent(inout) :: p(..)
        status         integer, optional, intent(out) :: status
    subroutine mlx_view(a, p, [status])
        a              type(mlx_array), intent(in) :: a
        p              integer(int64), pointer, intent(inout) :: p(..)
        status         integer, optional, intent(out) :: status
    subroutine mlx_view(a, p, [status])
        a              type(mlx_array), intent(in) :: a
        p              logical(c_bool), pointer, intent(inout) :: p(..)
        status         integer, optional, intent(out) :: status
```

## `mlx_alloc`

*Module* `mlxf_transfer`; *contract:* [4. Data in and out](policies/binding_contract_policy.md#4-data-in-and-out)

```text
generic mlx_alloc
    function mlx_alloc(fshape, mold, view, [status], [zero_copy])
        fshape         integer, intent(in) :: fshape(:)
        mold           real(real32), intent(in) :: mold
        view           real(real32), pointer, intent(inout) :: view(..)
        status         integer, optional, intent(out) :: status
        zero_copy      logical, optional, intent(out) :: zero_copy
        result         type(mlx_array) :: a
    function mlx_alloc(fshape, mold, view, [status], [zero_copy])
        fshape         integer, intent(in) :: fshape(:)
        mold           real(real64), intent(in) :: mold
        view           real(real64), pointer, intent(inout) :: view(..)
        status         integer, optional, intent(out) :: status
        zero_copy      logical, optional, intent(out) :: zero_copy
        result         type(mlx_array) :: a
    function mlx_alloc(fshape, mold, view, [status], [zero_copy])
        fshape         integer, intent(in) :: fshape(:)
        mold           complex(real32), intent(in) :: mold
        view           complex(real32), pointer, intent(inout) :: view(..)
        status         integer, optional, intent(out) :: status
        zero_copy      logical, optional, intent(out) :: zero_copy
        result         type(mlx_array) :: a
    function mlx_alloc(fshape, mold, view, [status], [zero_copy])
        fshape         integer, intent(in) :: fshape(:)
        mold           integer(int32), intent(in) :: mold
        view           integer(int32), pointer, intent(inout) :: view(..)
        status         integer, optional, intent(out) :: status
        zero_copy      logical, optional, intent(out) :: zero_copy
        result         type(mlx_array) :: a
    function mlx_alloc(fshape, mold, view, [status], [zero_copy])
        fshape         integer, intent(in) :: fshape(:)
        mold           integer(int8), intent(in) :: mold
        view           integer(int8), pointer, intent(inout) :: view(..)
        status         integer, optional, intent(out) :: status
        zero_copy      logical, optional, intent(out) :: zero_copy
        result         type(mlx_array) :: a
    function mlx_alloc(fshape, mold, view, [status], [zero_copy])
        fshape         integer, intent(in) :: fshape(:)
        mold           integer(int16), intent(in) :: mold
        view           integer(int16), pointer, intent(inout) :: view(..)
        status         integer, optional, intent(out) :: status
        zero_copy      logical, optional, intent(out) :: zero_copy
        result         type(mlx_array) :: a
    function mlx_alloc(fshape, mold, view, [status], [zero_copy])
        fshape         integer, intent(in) :: fshape(:)
        mold           integer(int64), intent(in) :: mold
        view           integer(int64), pointer, intent(inout) :: view(..)
        status         integer, optional, intent(out) :: status
        zero_copy      logical, optional, intent(out) :: zero_copy
        result         type(mlx_array) :: a
    function mlx_alloc(fshape, mold, view, [status], [zero_copy])
        fshape         integer, intent(in) :: fshape(:)
        mold           logical(c_bool), intent(in) :: mold
        view           logical(c_bool), pointer, intent(inout) :: view(..)
        status         integer, optional, intent(out) :: status
        zero_copy      logical, optional, intent(out) :: zero_copy
        result         type(mlx_array) :: a
```

## `mlx_eval`

*Module* `mlxf_array`; *contract:* [3. Lifetime](policies/binding_contract_policy.md#3-lifetime)

```text
generic mlx_eval
    subroutine mlx_eval(a, [status])
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_eval(arrays, [status])
        arrays         type(mlx_array), intent(in) :: arrays(:)
        status         integer, optional, intent(out) :: status
```

## `mlx_async_eval`

*Module* `mlxf_array`; *contract:* [3. Lifetime](policies/binding_contract_policy.md#3-lifetime)

```text
generic mlx_async_eval
    subroutine mlx_async_eval(a, [status])
        a              type(mlx_array), intent(in) :: a
        status         integer, optional, intent(out) :: status
    subroutine mlx_async_eval(arrays, [status])
        arrays         type(mlx_array), intent(in) :: arrays(:)
        status         integer, optional, intent(out) :: status
```

## `mlx_synchronize`

*Module* `mlxf_stream`; *contract:* [16. Streams, device availability and Metal capture](policies/binding_contract_policy.md#16-streams-device-availability-and-metal-capture)

```text
generic mlx_synchronize
    subroutine mlx_synchronize(stream, [status])
        stream         type(mlx_stream), intent(in) :: stream
        status         integer, optional, intent(out) :: status
        ! waits for the work queued on stream; with status, a failure returns with MLX usable
```

*Module* `mlxf_array`; *contract:* [3. Lifetime](policies/binding_contract_policy.md#3-lifetime)

```text
generic mlx_synchronize: waiting for queued work: on every device (here), or on one stream (the stream module's specific)
    subroutine mlx_synchronize([status])
        status         integer, optional, intent(out) :: status
```

## `mlx_is_live`

*Module* `mlxf_array`; *contract:* [3. Lifetime](policies/binding_contract_policy.md#3-lifetime)

```text
    function mlx_is_live(a)
        a              type(mlx_array), intent(in) :: a
        result         logical
```

## `exp`

*Module* `mlxf_array`; *contract:* [3. Lifetime](policies/binding_contract_policy.md#3-lifetime)

```text
generic exp
    function exp(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `real`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
generic real
    function real(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! Fortran's real(a): the real part of a complex array, otherwise a float32 copy, as Fortran's default real
```

## `aimag`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
generic aimag
    function aimag(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the imaginary part of a complex array
```

## `conjg`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
generic conjg
    function conjg(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the complex conjugate
```

## `sqrt`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
generic sqrt
    function sqrt(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the elementwise square root
```

## `mlx_astype`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
    function mlx_astype(a, dtype)
        a              type(mlx_array), intent(in) :: a
        dtype          integer, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! a converted to dtype, one of MLX_DTYPES
```

## `mlx_bitcast`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
    function mlx_bitcast(a, dtype)
        a              type(mlx_array), intent(in) :: a
        dtype          integer, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! a's bytes read as dtype, one of MLX_DTYPES (MLX's view; mlx_view is the Fortran pointer view): no value is converted. Where the item sizes differ, the first Fortran dimension scales by their ratio, so a float32 (2 n, ...) array whose pairs along dimension 1 are (real, imaginary) reads as complex64 (n, ...)
```

## `max`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
generic max
    function max(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! Fortran's max(a, b) elementwise; a scalar operand is weak and takes the array's kind
    function max(a, b)
        a              type(mlx_array), intent(in) :: a
        b              real(real32), intent(in) :: b
        result         type(mlx_array) :: r
    function max(a, b)
        a              real(real32), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
    function max(a, b)
        a              type(mlx_array), intent(in) :: a
        b              real(real64), intent(in) :: b
        result         type(mlx_array) :: r
    function max(a, b)
        a              real(real64), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
```

## `merge`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
generic merge
    function merge(tsource, fsource, mask)
        tsource        type(mlx_array), intent(in) :: tsource
        fsource        type(mlx_array), intent(in) :: fsource
        mask           type(mlx_array), intent(in) :: mask
        result         type(mlx_array) :: r
        ! Fortran's merge(tsource, fsource, mask) elementwise, mask a boolean array
```

## `cmplx`

*Module* `mlxf_ops_elementwise`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
generic cmplx
    function cmplx(x, y)
        x              type(mlx_array), intent(in) :: x
        y              type(mlx_array), intent(in) :: y
        result         type(mlx_array) :: r
        ! Fortran's cmplx(x, y) as x + i y in complex64; a non-finite y spoils the real part too
```

## `reshape`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic reshape
    function reshape(a, shape)
        a              type(mlx_array), intent(in) :: a
        shape          integer, intent(in) :: shape(:)
        result         type(mlx_array) :: r
        ! Fortran's column-major reshape: the reversed shape gives MLX's row-major reshape of the same bytes
```

## `mlx_permute`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_permute(a, order)
        a              type(mlx_array), intent(in) :: a
        order          integer, intent(in) :: order(:)
        result         type(mlx_array) :: r
        ! dimension i of the result is dimension order(i) of a; order is a permutation of 1 to the rank
```

## `transpose`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic transpose
    function transpose(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! swaps dimensions 1 and 2, every other dimension a batch; MLX's transpose of a matrix, its matrix transpose of a higher rank
```

## `mlx_concatenate`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_concatenate(arrays, [dim])
        arrays         type(mlx_array), intent(in) :: arrays(:)
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the arrays joined along Fortran dimension dim, their other extents agreeing; without dim, the elements of each in array element order, joined into a rank-1 result
```

## `mlx_slice`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_slice
    function mlx_slice(a, lower, upper, [stride])
        a              type(mlx_array), intent(in) :: a
        lower          integer, intent(in) :: lower(:)
        upper          integer, intent(in) :: upper(:)
        stride         integer, optional, intent(in) :: stride(:)
        result         type(mlx_array) :: r
        ! the section lower:upper:stride of a, inclusive and 1-based per dimension, stride 1 by default
    function mlx_slice(a, start, dims, slice_sizes)
        a              type(mlx_array), intent(in) :: a
        start          type(mlx_array), intent(in) :: start
        dims           integer, intent(in) :: dims(:)
        slice_sizes    integer, intent(in) :: slice_sizes(:)
        result         type(mlx_array) :: r
        ! the section of a whose first element is at the 1-based positions start (a rank-1 integer array of the graph, one per listed dimension) and whose extents are slice_sizes, one per dimension of a; a section that leaves a is not checked and reads outside it
```

## `mlx_take_along_dim`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_take_along_dim(a, indices, dim)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        dim            integer, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the elements of a at 1-based integer indices along dim; MLX checks no bounds, so an index of 0 wraps to the last element
```

## `mlx_take`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_take(a, indices, [dim])
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the slices of a at 1-based integer indices along dim, the indices' Fortran shape taking the place of dimension dim: r(.., i1, .., ik, ..) = a(.., indices(i1, .., ik), ..). Without dim, the elements at 1-based positions in array element order, in the indices' shape. MLX checks no bounds: an index of 0 wraps to the end
```

## `sum`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic sum
    function sum(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's sum: along dim, or over every dimension without it
    function sum(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! sum over the dimensions dims
```

## `minval`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic minval
    function minval(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's minval: along dim, or over every dimension without it
    function minval(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! minval over the dimensions dims
```

## `mlx_logsumexp`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_logsumexp
    function mlx_logsumexp(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! log(sum(exp(a))), computed stably by MLX: along dim, or over every dimension without it
    function mlx_logsumexp(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! mlx_logsumexp over the dimensions dims
```

## `mlx_cumsum`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_cumsum(a, [dim], [reverse], [inclusive])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        reverse        logical, optional, intent(in) :: reverse
        inclusive      logical, optional, intent(in) :: inclusive
        result         type(mlx_array) :: r
        ! the running sum along dim; without dim, of the elements in array element order, rank 1. reverse scans from the last element; an exclusive scan leaves each element out of its own result
```

## `minloc`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic minloc
    function minloc(a, dim, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's minloc(a, dim): 1-based int32 positions, the first on ties
    function minloc(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! Fortran's minloc(a): the subscripts of the first minimum in array element order, a rank-1 int32 array
```

## `mlx_zeros`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_zeros(shape, [dtype])
        shape          integer, intent(in) :: shape(:)
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! a zero array of Fortran shape shape, float32 unless dtype is given
```

## `mlx_arange`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_arange(start, stop, [step], [dtype])
        start          real(real64), intent(in) :: start
        stop           real(real64), intent(in) :: stop
        step           real(real64), optional, intent(in) :: step
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! start, start + step, ... below stop (stop excluded, as MLX's arange), float32 unless dtype is given
```

## `abs`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic abs
    function abs(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the absolute value (the modulus of a complex64 array, as float32)
```

## `sin`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic sin
    function sin(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `cos`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic cos
    function cos(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `tan`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic tan
    function tan(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `sinh`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic sinh
    function sinh(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `cosh`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic cosh
    function cosh(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `tanh`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic tanh
    function tanh(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `log`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic log
    function log(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the natural logarithm
```

## `log10`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic log10
    function log10(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `erf`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic erf
    function erf(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `asin`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic asin
    function asin(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the inverse functions, as Fortran's intrinsics
```

## `acos`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic acos
    function acos(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `atan`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic atan
    function atan(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `asinh`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic asinh
    function asinh(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `acosh`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic acosh
    function acosh(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `atanh`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic atanh
    function atanh(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `floor`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic floor
    function floor(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! floor, ceiling and aint (truncation) keep the input's kind: a float result, unlike Fortran's integer floor and ceiling
```

## `ceiling`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic ceiling
    function ceiling(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `aint`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic aint
    function aint(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
```

## `mlx_sign`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_sign(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the signum: -1, 0 or 1 (one argument, unlike Fortran's sign(a, b))
```

## `mlx_sigmoid`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_sigmoid(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! 1 / (1 + exp(-a))
```

## `mlx_square`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_square(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! a*a
```

## `mlx_reciprocal`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_reciprocal(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! 1 / a
```

## `mlx_rsqrt`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_rsqrt(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! 1 / sqrt(a)
```

## `mlx_expm1`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_expm1(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! exp(a) - 1, accurate near 0
```

## `mlx_log1p`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_log1p(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! log(1 + a), accurate near 0
```

## `mlx_log2`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_log2(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the base-2 logarithm
```

## `mlx_erfinv`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_erfinv(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the inverse of erf on (-1, 1)
```

## `mlx_degrees`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_degrees(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! radians to degrees
```

## `mlx_radians`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_radians(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! degrees to radians
```

## `mlx_stop_gradient`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_stop_gradient(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! a with no gradient flowing through it (its values unchanged)
```

## `mlx_copy`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_copy(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! a new graph node holding a copy of a (assignment shares the node instead)
```

## `mlx_isnan`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_isnan(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! true where a is NaN
```

## `mlx_isinf`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_isinf(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! true where a is infinite, of either sign
```

## `mlx_isfinite`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_isfinite(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! true where a is neither infinite nor NaN
```

## `mlx_isposinf`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_isposinf(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! true where a is +Inf
```

## `mlx_isneginf`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_isneginf(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! true where a is -Inf
```

## `mlx_round`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_round(a, [decimals])
        a              type(mlx_array), intent(in) :: a
        decimals       integer, optional, intent(in) :: decimals
        result         type(mlx_array) :: r
        ! rounded to decimals places (default 0), halves to even: 0.5 -> 0, 1.5 -> 2, 2.5 -> 2 (unlike anint)
```

## `mlx_clip`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_clip
    function mlx_clip(a, a_min, a_max)
        a              type(mlx_array), intent(in) :: a
        a_min          type(mlx_array), intent(in) :: a_min
        a_max          type(mlx_array), intent(in) :: a_max
        result         type(mlx_array) :: r
        ! a limited to [a_min, a_max] elementwise; the bounds broadcast, and scalar bounds are weak
    function mlx_clip(a, a_min, a_max)
        a              type(mlx_array), intent(in) :: a
        a_min          real(real32), intent(in) :: a_min
        a_max          real(real32), intent(in) :: a_max
        result         type(mlx_array) :: r
    function mlx_clip(a, a_min, a_max)
        a              type(mlx_array), intent(in) :: a
        a_min          real(real64), intent(in) :: a_min
        a_max          real(real64), intent(in) :: a_max
        result         type(mlx_array) :: r
```

## `mlx_nan_to_num`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_nan_to_num(a, [nan], [posinf], [neginf])
        a              type(mlx_array), intent(in) :: a
        nan            real(real32), optional, intent(in) :: nan
        posinf         real(real32), optional, intent(in) :: posinf
        neginf         real(real32), optional, intent(in) :: neginf
        result         type(mlx_array) :: r
        ! NaN replaced by nan (default 0), the infinities by posinf and neginf (default the largest finite values of a's kind)
```

## `atan2`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic atan2
    function atan2(y, x)
        y              type(mlx_array), intent(in) :: y
        x              type(mlx_array), intent(in) :: x
        result         type(mlx_array) :: r
        ! atan2(y, x), the angle of (x, y), in Fortran's argument order
    function atan2(y, x)
        y              type(mlx_array), intent(in) :: y
        x              real(real32), intent(in) :: x
        result         type(mlx_array) :: r
    function atan2(y, x)
        y              real(real32), intent(in) :: y
        x              type(mlx_array), intent(in) :: x
        result         type(mlx_array) :: r
    function atan2(y, x)
        y              type(mlx_array), intent(in) :: y
        x              real(real64), intent(in) :: x
        result         type(mlx_array) :: r
    function atan2(y, x)
        y              real(real64), intent(in) :: y
        x              type(mlx_array), intent(in) :: x
        result         type(mlx_array) :: r
```

## `modulo`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic modulo
    function modulo(a, p)
        a              type(mlx_array), intent(in) :: a
        p              type(mlx_array), intent(in) :: p
        result         type(mlx_array) :: r
        ! Fortran's modulo(a, p): a - floor(a/p) p, with the sign of p
    function modulo(a, p)
        a              type(mlx_array), intent(in) :: a
        p              real(real32), intent(in) :: p
        result         type(mlx_array) :: r
    function modulo(a, p)
        a              real(real32), intent(in) :: a
        p              type(mlx_array), intent(in) :: p
        result         type(mlx_array) :: r
    function modulo(a, p)
        a              type(mlx_array), intent(in) :: a
        p              real(real64), intent(in) :: p
        result         type(mlx_array) :: r
    function modulo(a, p)
        a              real(real64), intent(in) :: a
        p              type(mlx_array), intent(in) :: p
        result         type(mlx_array) :: r
```

## `min`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic min
    function min(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! Fortran's min(a, b) elementwise
    function min(a, b)
        a              type(mlx_array), intent(in) :: a
        b              real(real32), intent(in) :: b
        result         type(mlx_array) :: r
    function min(a, b)
        a              real(real32), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
    function min(a, b)
        a              type(mlx_array), intent(in) :: a
        b              real(real64), intent(in) :: b
        result         type(mlx_array) :: r
    function min(a, b)
        a              real(real64), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
```

## `mlx_logaddexp`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_logaddexp
    function mlx_logaddexp(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! log(exp(a) + exp(b)) without overflow
    function mlx_logaddexp(a, b)
        a              type(mlx_array), intent(in) :: a
        b              real(real32), intent(in) :: b
        result         type(mlx_array) :: r
    function mlx_logaddexp(a, b)
        a              real(real32), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
    function mlx_logaddexp(a, b)
        a              type(mlx_array), intent(in) :: a
        b              real(real64), intent(in) :: b
        result         type(mlx_array) :: r
    function mlx_logaddexp(a, b)
        a              real(real64), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
```

## `mlx_floor_divide`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_floor_divide
    function mlx_floor_divide(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! floor(a / b), the quotient of modulo
    function mlx_floor_divide(a, b)
        a              type(mlx_array), intent(in) :: a
        b              real(real32), intent(in) :: b
        result         type(mlx_array) :: r
    function mlx_floor_divide(a, b)
        a              real(real32), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
    function mlx_floor_divide(a, b)
        a              type(mlx_array), intent(in) :: a
        b              real(real64), intent(in) :: b
        result         type(mlx_array) :: r
    function mlx_floor_divide(a, b)
        a              real(real64), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
```

## `mlx_divmod`

*Module* `mlxf_ops_math`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_divmod(a, b, quotient, remainder)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        quotient       type(mlx_array), intent(out) :: quotient
        remainder      type(mlx_array), intent(out) :: remainder
        ! the quotient floor(a / b) and the remainder modulo(a, b) of one MLX node
```

## `mlx_isclose`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_isclose(a, b, [rtol], [atol], [equal_nan])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        rtol           real(real64), optional, intent(in) :: rtol
        atol           real(real64), optional, intent(in) :: atol
        equal_nan      logical, optional, intent(in) :: equal_nan
        result         type(mlx_array) :: r
        ! |a - b| <= atol + rtol |b| elementwise (defaults rtol = 1e-5, atol = 1e-8); NaNs are unequal unless equal_nan
```

## `mlx_allclose`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_allclose(a, b, [rtol], [atol], [equal_nan])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        rtol           real(real64), optional, intent(in) :: rtol
        atol           real(real64), optional, intent(in) :: atol
        equal_nan      logical, optional, intent(in) :: equal_nan
        result         type(mlx_array) :: r
        ! whether mlx_isclose holds everywhere: a rank-0 boolean array
```

## `mlx_array_equal`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_array_equal(a, b, [equal_nan])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        equal_nan      logical, optional, intent(in) :: equal_nan
        result         type(mlx_array) :: r
        ! whether a and b have the same shape and values (of any dtypes): a rank-0 boolean array
```

## `iand`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic iand
    function iand(i, j)
        i              type(mlx_array), intent(in) :: i
        j              type(mlx_array), intent(in) :: j
        result         type(mlx_array) :: r
        ! the bitwise and, or and exclusive or of integer arrays, as Fortran's iand, ior and ieor
    function iand(i, j)
        i              type(mlx_array), intent(in) :: i
        j              integer, intent(in) :: j
        result         type(mlx_array) :: r
    function iand(i, j)
        i              integer, intent(in) :: i
        j              type(mlx_array), intent(in) :: j
        result         type(mlx_array) :: r
```

## `ior`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic ior
    function ior(i, j)
        i              type(mlx_array), intent(in) :: i
        j              type(mlx_array), intent(in) :: j
        result         type(mlx_array) :: r
        ! bitwise or
    function ior(i, j)
        i              type(mlx_array), intent(in) :: i
        j              integer, intent(in) :: j
        result         type(mlx_array) :: r
    function ior(i, j)
        i              integer, intent(in) :: i
        j              type(mlx_array), intent(in) :: j
        result         type(mlx_array) :: r
```

## `ieor`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic ieor
    function ieor(i, j)
        i              type(mlx_array), intent(in) :: i
        j              type(mlx_array), intent(in) :: j
        result         type(mlx_array) :: r
        ! bitwise exclusive or
    function ieor(i, j)
        i              type(mlx_array), intent(in) :: i
        j              integer, intent(in) :: j
        result         type(mlx_array) :: r
    function ieor(i, j)
        i              integer, intent(in) :: i
        j              type(mlx_array), intent(in) :: j
        result         type(mlx_array) :: r
```

## `not`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic not
    function not(i)
        i              type(mlx_array), intent(in) :: i
        result         type(mlx_array) :: r
        ! the bitwise complement, as Fortran's not
```

## `shiftl`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic shiftl
    function shiftl(i, shift)
        i              type(mlx_array), intent(in) :: i
        shift          type(mlx_array), intent(in) :: shift
        result         type(mlx_array) :: r
        ! i shifted left by shift bits, zeros shifted in, as Fortran's shiftl
    function shiftl(i, shift)
        i              type(mlx_array), intent(in) :: i
        shift          integer, intent(in) :: shift
        result         type(mlx_array) :: r
```

## `mlx_right_shift`

*Module* `mlxf_ops_logic`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_right_shift
    function mlx_right_shift(i, shift)
        i              type(mlx_array), intent(in) :: i
        shift          type(mlx_array), intent(in) :: shift
        result         type(mlx_array) :: r
        ! i shifted right by shift bits: arithmetic (the sign bit copied in) on signed integers, as Fortran's shifta, unlike its logical shiftr
    function mlx_right_shift(i, shift)
        i              type(mlx_array), intent(in) :: i
        shift          integer, intent(in) :: shift
        result         type(mlx_array) :: r
```

## `mlx_ones`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_ones(shape, [dtype])
        shape          integer, intent(in) :: shape(:)
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! an array of ones of Fortran shape shape, float32 unless dtype is given
```

## `mlx_full`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_full
    function mlx_full(shape, vals, [dtype])
        shape          integer, intent(in) :: shape(:)
        vals           type(mlx_array), intent(in) :: vals
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! an array of Fortran shape shape filled with vals, broadcast with leading dimensions aligned; the kind is vals' unless dtype is given
    function mlx_full(shape, vals, [dtype])
        shape          integer, intent(in) :: shape(:)
        vals           real(real32), intent(in) :: vals
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! the scalar fills: float32 for a real value and int32 for an integer one unless dtype is given
    function mlx_full(shape, vals, [dtype])
        shape          integer, intent(in) :: shape(:)
        vals           real(real64), intent(in) :: vals
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
    function mlx_full(shape, vals, [dtype])
        shape          integer, intent(in) :: shape(:)
        vals           integer, intent(in) :: vals
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
```

## `mlx_zeros_like`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_zeros_like(a, [dtype])
        a              type(mlx_array), intent(in) :: a
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! zeros of a's shape, of a's kind unless dtype is given
```

## `mlx_ones_like`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_ones_like(a, [dtype])
        a              type(mlx_array), intent(in) :: a
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! ones of a's shape, of a's kind unless dtype is given
```

## `mlx_full_like`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_full_like
    function mlx_full_like(a, vals, [dtype])
        a              type(mlx_array), intent(in) :: a
        vals           type(mlx_array), intent(in) :: vals
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! vals broadcast to a's shape, of a's kind unless dtype is given
    function mlx_full_like(a, vals, [dtype])
        a              type(mlx_array), intent(in) :: a
        vals           real(real32), intent(in) :: vals
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
    function mlx_full_like(a, vals, [dtype])
        a              type(mlx_array), intent(in) :: a
        vals           real(real64), intent(in) :: vals
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
    function mlx_full_like(a, vals, [dtype])
        a              type(mlx_array), intent(in) :: a
        vals           integer, intent(in) :: vals
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
```

## `product`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic product
    function product(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's product: along dim, or over every dimension without it
    function product(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! product over the dimensions dims
```

## `maxval`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic maxval
    function maxval(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's maxval: along dim, or over every dimension without it
    function maxval(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! maxval over the dimensions dims
```

## `all`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic all
    function all(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's all, a nonzero element counting as true: along dim, or over every dimension without it
    function all(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! all over the dimensions dims
```

## `any`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic any
    function any(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's any, a nonzero element counting as true: along dim, or over every dimension without it
    function any(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! any over the dimensions dims
```

## `count`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic count
    function count(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's count of the true (nonzero) elements, int32: along dim, or over every dimension without it
    function count(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! count over the dimensions dims
```

## `maxloc`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic maxloc
    function maxloc(a, dim, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! Fortran's maxloc(a, dim): 1-based int32 positions, the first on ties
    function maxloc(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! Fortran's maxloc(a): the subscripts of the first maximum in array element order, a rank-1 int32 array
```

## `mlx_mean`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_mean
    function mlx_mean(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! the arithmetic mean: along dim, or over every dimension without it
    function mlx_mean(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! mlx_mean over the dimensions dims
```

## `mlx_median`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_median
    function mlx_median(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! the median, the mean of the two middle elements of an even count: along dim, or over every dimension without it
    function mlx_median(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! mlx_median over the dimensions dims
```

## `mlx_var`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_var
    function mlx_var(a, [dim], [keepdims], [ddof])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        ddof           integer, optional, intent(in) :: ddof
        result         type(mlx_array) :: r
        ! the variance, its divisor the count less ddof (0 by default): along dim, or over every dimension without it
    function mlx_var(a, dims, [keepdims], [ddof])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        ddof           integer, optional, intent(in) :: ddof
        result         type(mlx_array) :: r
        ! mlx_var over the dimensions dims
```

## `mlx_std`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_std
    function mlx_std(a, [dim], [keepdims], [ddof])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        ddof           integer, optional, intent(in) :: ddof
        result         type(mlx_array) :: r
        ! the standard deviation, the square root of mlx_var: along dim, or over every dimension without it
    function mlx_std(a, dims, [keepdims], [ddof])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        ddof           integer, optional, intent(in) :: ddof
        result         type(mlx_array) :: r
        ! mlx_std over the dimensions dims
```

## `mlx_cumprod`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_cumprod(a, [dim], [reverse], [inclusive])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        reverse        logical, optional, intent(in) :: reverse
        inclusive      logical, optional, intent(in) :: inclusive
        result         type(mlx_array) :: r
        ! the running product along dim; without dim, of the elements in array element order, rank 1. reverse scans from the last element; an exclusive scan leaves each element out of its own result
```

## `mlx_cummax`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_cummax(a, [dim], [reverse], [inclusive])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        reverse        logical, optional, intent(in) :: reverse
        inclusive      logical, optional, intent(in) :: inclusive
        result         type(mlx_array) :: r
        ! the running maximum along dim; without dim, of the elements in array element order, rank 1. reverse scans from the last element; an exclusive scan leaves each element out of its own result
```

## `mlx_cummin`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_cummin(a, [dim], [reverse], [inclusive])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        reverse        logical, optional, intent(in) :: reverse
        inclusive      logical, optional, intent(in) :: inclusive
        result         type(mlx_array) :: r
        ! the running minimum along dim; without dim, of the elements in array element order, rank 1. reverse scans from the last element; an exclusive scan leaves each element out of its own result
```

## `mlx_logcumsumexp`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_logcumsumexp(a, [dim], [reverse], [inclusive])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        reverse        logical, optional, intent(in) :: reverse
        inclusive      logical, optional, intent(in) :: inclusive
        result         type(mlx_array) :: r
        ! the running log(sum(exp(a))) (MLX's stable form) along dim; without dim, of the elements in array element order, rank 1. reverse scans from the last element; an exclusive scan leaves each element out of its own result
```

## `mlx_softmax`

*Module* `mlxf_ops_reduce`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_softmax
    function mlx_softmax(a, [dim], [precise])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        precise        logical, optional, intent(in) :: precise
        result         type(mlx_array) :: r
        ! the softmax along dim, dimension 1 when it is absent; precise computes it in a more stable, slower form
    function mlx_softmax(a, dims, [precise])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        precise        logical, optional, intent(in) :: precise
        result         type(mlx_array) :: r
        ! the softmax over the dimensions dims jointly
```

## `mlx_sort`

*Module* `mlxf_ops_sort`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_sort(a, [dim])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the elements in ascending order
```

## `mlx_argsort`

*Module* `mlxf_ops_sort`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_argsort(a, [dim])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the 1-based positions that sort a in ascending order
```

## `mlx_partition`

*Module* `mlxf_ops_sort`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_partition(a, kth, [dim])
        a              type(mlx_array), intent(in) :: a
        kth            integer, intent(in) :: kth
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! a rearrangement with the element of sorted position kth in place: no element before it is larger and none after it smaller; the order inside the two parts is not defined
```

## `mlx_argpartition`

*Module* `mlxf_ops_sort`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_argpartition(a, kth, [dim])
        a              type(mlx_array), intent(in) :: a
        kth            integer, intent(in) :: kth
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the 1-based positions that partition a as mlx_partition does
```

## `mlx_topk`

*Module* `mlxf_ops_sort`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_topk(a, k, [dim])
        a              type(mlx_array), intent(in) :: a
        k              integer, intent(in) :: k
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the k largest elements, in no defined order
```

## `mlx_squeeze`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_squeeze
    function mlx_squeeze(a, [dim])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! a without its dimensions of extent 1: all of them, or dimension dim
    function mlx_squeeze(a, dims)
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! a without the dimensions dims, each of extent 1
```

## `mlx_expand_dims`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_expand_dims
    function mlx_expand_dims(a, dim)
        a              type(mlx_array), intent(in) :: a
        dim            integer, intent(in) :: dim
        result         type(mlx_array) :: r
        ! a with a new dimension of extent 1 at position dim of the result
    function mlx_expand_dims(a, dims)
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! a with new dimensions of extent 1 at the positions dims of the result
```

## `mlx_flatten`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_flatten(a, [start_dim], [end_dim])
        a              type(mlx_array), intent(in) :: a
        start_dim      integer, optional, intent(in) :: start_dim
        end_dim        integer, optional, intent(in) :: end_dim
        result         type(mlx_array) :: r
        ! dimensions start_dim to end_dim (1 and the rank by default) merged into one, in array element order
```

## `mlx_unflatten`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_unflatten(a, dim, shape)
        a              type(mlx_array), intent(in) :: a
        dim            integer, intent(in) :: dim
        shape          integer, intent(in) :: shape(:)
        result         type(mlx_array) :: r
        ! dimension dim split into the dimensions of Fortran shape shape, in array element order
```

## `mlx_broadcast_to`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_broadcast_to(a, shape)
        a              type(mlx_array), intent(in) :: a
        shape          integer, intent(in) :: shape(:)
        result         type(mlx_array) :: r
        ! a broadcast to Fortran shape shape, its leading dimensions aligned
```

## `mlx_broadcast_arrays`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_broadcast_arrays(arrays, results)
        arrays         type(mlx_array), intent(in) :: arrays(:)
        results        type(mlx_array), allocatable, intent(out) :: results(:)
        ! the arrays broadcast against each other to one shape, their leading dimensions aligned
```

## `mlx_tile`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_tile(a, reps)
        a              type(mlx_array), intent(in) :: a
        reps           integer, intent(in) :: reps(:)
        result         type(mlx_array) :: r
        ! a repeated reps(d) times along dimension d
```

## `mlx_repeat`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_repeat(a, repeats, [dim])
        a              type(mlx_array), intent(in) :: a
        repeats        integer, intent(in) :: repeats
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! every element repeated repeats times along dim; without dim, of the elements in array element order (a rank-1 result)
```

## `mlx_pad`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_pad
    function mlx_pad(a, width, [value], [mode])
        a              type(mlx_array), intent(in) :: a
        width          integer, intent(in) :: width
        value          type(mlx_array), optional, intent(in) :: value
        mode           character(len=*), optional, intent(in) :: mode
        result         type(mlx_array) :: r
        ! a padded by width elements on both sides of every dimension, with value (zero by default) or, in mode 'edge', with the border elements
    function mlx_pad(a, low, high, [value], [mode])
        a              type(mlx_array), intent(in) :: a
        low            integer, intent(in) :: low(:)
        high           integer, intent(in) :: high(:)
        value          type(mlx_array), optional, intent(in) :: value
        mode           character(len=*), optional, intent(in) :: mode
        result         type(mlx_array) :: r
        ! a padded by low(d) elements before and high(d) elements after dimension d
```

## `mlx_flip`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_flip
    function mlx_flip(a, [dim])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! a reversed along dim, or along every dimension without it
    function mlx_flip(a, dims)
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! a reversed along the dimensions dims
```

## `cshift`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic cshift
    function cshift(a, shift, [dim])
        a              type(mlx_array), intent(in) :: a
        shift          integer, intent(in) :: shift
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! Fortran's cshift(a, shift, dim): element i of the result is element i + shift of a along dim (1 by default), circularly; MLX's roll by -shift
    function cshift(a, shift, dims)
        a              type(mlx_array), intent(in) :: a
        shift          integer, intent(in) :: shift(:)
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! a circular shift by shift(i) along dimension dims(i), one after the other
```

## `mlx_movedim`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_movedim(a, source, destination)
        a              type(mlx_array), intent(in) :: a
        source         integer, intent(in) :: source
        destination    integer, intent(in) :: destination
        result         type(mlx_array) :: r
        ! dimension source moved to position destination, the others keeping their order
```

## `mlx_swapdims`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_swapdims(a, dim1, dim2)
        a              type(mlx_array), intent(in) :: a
        dim1           integer, intent(in) :: dim1
        dim2           integer, intent(in) :: dim2
        result         type(mlx_array) :: r
        ! dimensions dim1 and dim2 exchanged
```

## `mlx_split`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_split
    subroutine mlx_split(a, num, parts, [dim])
        a              type(mlx_array), intent(in) :: a
        num            integer, intent(in) :: num
        parts          type(mlx_array), allocatable, intent(out) :: parts(:)
        dim            integer, optional, intent(in) :: dim
        ! a cut into num equal parts along dim, the last dimension when absent
    subroutine mlx_split(a, indices, parts, [dim])
        a              type(mlx_array), intent(in) :: a
        indices        integer, intent(in) :: indices(:)
        parts          type(mlx_array), allocatable, intent(out) :: parts(:)
        dim            integer, optional, intent(in) :: dim
        ! a cut along dim, the last dimension when absent, before each 1-based position of indices: indices [4, 7] give the parts 1:3, 4:6 and 7:
```

## `mlx_stack`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_stack(arrays, [dim])
        arrays         type(mlx_array), intent(in) :: arrays(:)
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the arrays, of one shape, joined along a new dimension at position dim of the result, the last when absent
```

## `mlx_unstack`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_unstack(a, parts, [dim])
        a              type(mlx_array), intent(in) :: a
        parts          type(mlx_array), allocatable, intent(out) :: parts(:)
        dim            integer, optional, intent(in) :: dim
        ! the slices of a along dim, the last dimension when absent, each without that dimension
```

## `mlx_atleast_1d`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_atleast_1d(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! a with rank at least one: a scalar becomes shape (1)
```

## `mlx_atleast_2d`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_atleast_2d(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! a with rank at least two: shape (n) becomes (n, 1)
```

## `mlx_atleast_3d`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_atleast_3d(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! a with rank at least three, by MLX's rule read in Fortran order: (n) becomes (1, n, 1) and (m, n) becomes (1, m, n)
```

## `mlx_diag`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_diag(a, [k])
        a              type(mlx_array), intent(in) :: a
        k              integer, optional, intent(in) :: k
        result         type(mlx_array) :: r
        ! of a vector, the matrix with it on diagonal k; of a matrix, its diagonal k. k > 0 is above the main diagonal of the Fortran matrix, elements (i, i + k), which is MLX's diagonal -k
```

## `mlx_diagonal`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_diagonal(a, [offset], [dim1], [dim2])
        a              type(mlx_array), intent(in) :: a
        offset         integer, optional, intent(in) :: offset
        dim1           integer, optional, intent(in) :: dim1
        dim2           integer, optional, intent(in) :: dim2
        result         type(mlx_array) :: r
        ! the elements (i along dim1, i + offset along dim2) of a, dimensions 1 and 2 by default; the diagonal is dimension 1 of the result and the other dimensions follow in order
```

## `mlx_trace`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_trace(a, [offset], [dim1], [dim2], [dtype])
        a              type(mlx_array), intent(in) :: a
        offset         integer, optional, intent(in) :: offset
        dim1           integer, optional, intent(in) :: dim1
        dim2           integer, optional, intent(in) :: dim2
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! the sum of mlx_diagonal(a, offset, dim1, dim2), in a's dtype unless dtype is given
```

## `mlx_tril`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_tril(a, [k])
        a              type(mlx_array), intent(in) :: a
        k              integer, optional, intent(in) :: k
        result         type(mlx_array) :: r
        ! the lower triangle of the Fortran matrix in dimensions 1 and 2: elements (i, j) with j <= i + k, the others zero. MLX sees the transpose, so this is its upper triangle with diagonal -k
```

## `mlx_triu`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_triu(a, [k])
        a              type(mlx_array), intent(in) :: a
        k              integer, optional, intent(in) :: k
        result         type(mlx_array) :: r
        ! the upper triangle of the Fortran matrix in dimensions 1 and 2: elements (i, j) with j >= i + k
```

## `mlx_diff`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_diff(a, [n], [dim])
        a              type(mlx_array), intent(in) :: a
        n              integer, optional, intent(in) :: n
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the n-th discrete difference along dim (1 and dimension 1 by default): a(i + 1) - a(i), applied n times
```

## `mlx_as_strided`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_as_strided(a, shape, strides, [offset])
        a              type(mlx_array), intent(in) :: a
        shape          integer, intent(in) :: shape(:)
        strides        integer, intent(in) :: strides(:)
        offset         integer, optional, intent(in) :: offset
        result         type(mlx_array) :: r
        ! a view of a's elements in array element order: element (i1, ..., ir) of the result is element 1 + offset + sum((i_d - 1)*strides(d)) of a, the strides in elements; nothing checks that it lies inside a. MLX strides over the buffer, so a strided a (a transpose, a flip) is made contiguous first
```

## `mlx_number_of_elements`

*Module* `mlxf_ops_shape`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_number_of_elements(a, [dims], [inverted], [dtype])
        a              type(mlx_array), intent(in) :: a
        dims           integer, optional, intent(in) :: dims(:)
        inverted       logical, optional, intent(in) :: inverted
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! the product of the extents of the dimensions dims (all by default) as a rank-0 array, its reciprocal when inverted; float32 unless dtype is given
```

## `mlx_identity`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_identity(n, [dtype])
        n              integer, intent(in) :: n
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! the n by n identity matrix, float32 unless dtype is given
```

## `mlx_eye`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_eye(n, [m], [k], [dtype])
        n              integer, intent(in) :: n
        m              integer, optional, intent(in) :: m
        k              integer, optional, intent(in) :: k
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! an (n, m) matrix (m = n by default) with ones on diagonal k, elements (i, i + k), and zeros elsewhere; MLX builds its transpose: m rows, n columns and diagonal -k
```

## `mlx_tri`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_tri(n, [m], [k], [dtype])
        n              integer, intent(in) :: n
        m              integer, optional, intent(in) :: m
        k              integer, optional, intent(in) :: k
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! an (n, m) matrix (m = n by default) with ones at and below diagonal k, elements (i, j) with j <= i + k; MLX's (n, m) triangle is the Fortran view's transpose, so one transpose node (a view) follows it
```

## `mlx_linspace`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_linspace(start, stop, [num], [endpoint], [dtype])
        start          real(real64), intent(in) :: start
        stop           real(real64), intent(in) :: stop
        num            integer, optional, intent(in) :: num
        endpoint       logical, optional, intent(in) :: endpoint
        dtype          integer, optional, intent(in) :: dtype
        result         type(mlx_array) :: r
        ! num (50 by default) evenly spaced values from start to stop, stop included unless endpoint is false; float32 unless dtype is given
```

## `mlx_meshgrid`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_meshgrid(arrays, grids, [sparse])
        arrays         type(mlx_array), intent(in) :: arrays(:)
        grids          type(mlx_array), allocatable, intent(out) :: grids(:)
        sparse         logical, optional, intent(in) :: sparse
        ! the coordinate grids of rank-1 arrays in matrix indexing: grid i has shape (n1, ..., nk) and varies along dimension i (extent 1 along the others when sparse). MLX numbers axes in the reverse order, so the list goes to it reversed and comes back reversed
```

## `mlx_bartlett`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_bartlett(m)
        m              integer, intent(in) :: m
        result         type(mlx_array) :: r
        ! the Bartlett (triangular) window of m points, float32
```

## `mlx_blackman`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_blackman(m)
        m              integer, intent(in) :: m
        result         type(mlx_array) :: r
        ! the Blackman window of m points, float32
```

## `mlx_hamming`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_hamming(m)
        m              integer, intent(in) :: m
        result         type(mlx_array) :: r
        ! the Hamming window of m points, float32
```

## `mlx_hanning`

*Module* `mlxf_ops_create`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_hanning(m)
        m              integer, intent(in) :: m
        result         type(mlx_array) :: r
        ! the Hann window of m points, float32
```

## `mlx_gather`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_gather
    function mlx_gather(a, indices, dims, slice_sizes)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices(:)
        dims           integer, intent(in) :: dims(:)
        slice_sizes    integer, intent(in) :: slice_sizes(:)
        result         type(mlx_array) :: r
        ! the slabs of a at the 1-based positions of one index array per listed dimension: a slab has extent slice_sizes(d) along dimension d of a and starts at the given positions along dims; the result has the slab's shape, then the index arrays' (broadcast) shape
    function mlx_gather(a, indices, dim, slice_sizes)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        dim            integer, intent(in) :: dim
        slice_sizes    integer, intent(in) :: slice_sizes(:)
        result         type(mlx_array) :: r
        ! mlx_gather along one dimension
```

## `mlx_scatter`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_scatter
    function mlx_scatter(a, indices, updates, dims)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices(:)
        updates        type(mlx_array), intent(in) :: updates
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! a with the slabs of updates written at the 1-based positions of one index array per listed dimension; updates has a's shape with extent 1 along dims, then the index arrays' shape. Where positions repeat, which update stays is not defined
    function mlx_scatter(a, indices, updates, dim)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        updates        type(mlx_array), intent(in) :: updates
        dim            integer, intent(in) :: dim
        result         type(mlx_array) :: r
```

## `mlx_scatter_add`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_scatter_add
    function mlx_scatter_add(a, indices, updates, dims)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices(:)
        updates        type(mlx_array), intent(in) :: updates
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! as mlx_scatter, the updates added to a: repeated positions accumulate
    function mlx_scatter_add(a, indices, updates, dim)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        updates        type(mlx_array), intent(in) :: updates
        dim            integer, intent(in) :: dim
        result         type(mlx_array) :: r
        ! one index array along dim: updates of rank(indices) + rank(a) are always slabs, as mlx_scatter's; otherwise indices and updates have a's rank and each update is added at its own position along dim, as mlx_put_along_dim writes it (the inverse of mlx_take_along_dim)
```

## `mlx_scatter_max`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_scatter_max
    function mlx_scatter_max(a, indices, updates, dims)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices(:)
        updates        type(mlx_array), intent(in) :: updates
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! as mlx_scatter, keeping the larger of a and every update at a position
    function mlx_scatter_max(a, indices, updates, dim)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        updates        type(mlx_array), intent(in) :: updates
        dim            integer, intent(in) :: dim
        result         type(mlx_array) :: r
```

## `mlx_scatter_min`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_scatter_min
    function mlx_scatter_min(a, indices, updates, dims)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices(:)
        updates        type(mlx_array), intent(in) :: updates
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! as mlx_scatter, keeping the smaller of a and every update at a position
    function mlx_scatter_min(a, indices, updates, dim)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        updates        type(mlx_array), intent(in) :: updates
        dim            integer, intent(in) :: dim
        result         type(mlx_array) :: r
```

## `mlx_scatter_prod`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_scatter_prod
    function mlx_scatter_prod(a, indices, updates, dims)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices(:)
        updates        type(mlx_array), intent(in) :: updates
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! as mlx_scatter, a multiplied by every update at a position
    function mlx_scatter_prod(a, indices, updates, dim)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        updates        type(mlx_array), intent(in) :: updates
        dim            integer, intent(in) :: dim
        result         type(mlx_array) :: r
```

## `mlx_put_along_dim`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_put_along_dim(a, indices, values, dim)
        a              type(mlx_array), intent(in) :: a
        indices        type(mlx_array), intent(in) :: indices
        values         type(mlx_array), intent(in) :: values
        dim            integer, intent(in) :: dim
        result         type(mlx_array) :: r
        ! a with values written at 1-based indices along dim, element by element: the inverse of mlx_take_along_dim; indices and values have a's rank and broadcast against it outside dim
```

## `mlx_masked_scatter`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_masked_scatter(a, mask, src)
        a              type(mlx_array), intent(in) :: a
        mask           type(mlx_array), intent(in) :: mask
        src            type(mlx_array), intent(in) :: src
        result         type(mlx_array) :: r
        ! a with the elements where mask holds replaced by the elements of src, taken in array element order; a mask of lower rank has the shape of a's last dimensions
```

## `mlx_searchsorted`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_searchsorted(sorted, values, [side])
        sorted         type(mlx_array), intent(in) :: sorted
        values         type(mlx_array), intent(in) :: values
        side           character(len=*), optional, intent(in) :: side
        result         type(mlx_array) :: r
        ! where each value would be inserted into the ascending rank-1 array sorted to keep it sorted: 1-based int32 positions from 1 to size + 1; side 'left' (the default) is before equal elements, 'right' after them
```

## `mlx_unique`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_unique(a, size, results, [fill])
        a              type(mlx_array), intent(in) :: a
        size           integer, intent(in) :: size
        results        type(mlx_array), allocatable, intent(out) :: results(:)
        fill           type(mlx_array), optional, intent(in) :: fill
        ! the distinct values of a, ascending, in size slots (unused ones hold fill, the smallest value by default), then the 1-based position in array element order of each first occurrence, the 1-based slot of every element (a's shape) and the count of each value (zero in an unused slot)
```

## `mlx_slice_update`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_slice_update
    function mlx_slice_update(a, update, lower, upper, [stride])
        a              type(mlx_array), intent(in) :: a
        update         type(mlx_array), intent(in) :: update
        lower          integer, intent(in) :: lower(:)
        upper          integer, intent(in) :: upper(:)
        stride         integer, optional, intent(in) :: stride(:)
        result         type(mlx_array) :: r
        ! a with its section lower:upper:stride (as mlx_slice takes them) replaced by update, broadcast to the section
    function mlx_slice_update(a, update, start, dims)
        a              type(mlx_array), intent(in) :: a
        update         type(mlx_array), intent(in) :: update
        start          type(mlx_array), intent(in) :: start
        dims           integer, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! a with update written from the 1-based positions start (a rank-1 integer array of the graph, one per listed dimension); update's extents are the section's
```

## `mlx_slice_update_add`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_slice_update_add(a, update, lower, upper, [stride])
        a              type(mlx_array), intent(in) :: a
        update         type(mlx_array), intent(in) :: update
        lower          integer, intent(in) :: lower(:)
        upper          integer, intent(in) :: upper(:)
        stride         integer, optional, intent(in) :: stride(:)
        result         type(mlx_array) :: r
        ! a with update added to its section lower:upper:stride
```

## `mlx_slice_update_max`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_slice_update_max(a, update, lower, upper, [stride])
        a              type(mlx_array), intent(in) :: a
        update         type(mlx_array), intent(in) :: update
        lower          integer, intent(in) :: lower(:)
        upper          integer, intent(in) :: upper(:)
        stride         integer, optional, intent(in) :: stride(:)
        result         type(mlx_array) :: r
        ! a with its section lower:upper:stride replaced by the larger of it and update
```

## `mlx_slice_update_min`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_slice_update_min(a, update, lower, upper, [stride])
        a              type(mlx_array), intent(in) :: a
        update         type(mlx_array), intent(in) :: update
        lower          integer, intent(in) :: lower(:)
        upper          integer, intent(in) :: upper(:)
        stride         integer, optional, intent(in) :: stride(:)
        result         type(mlx_array) :: r
        ! a with its section lower:upper:stride replaced by the smaller of it and update
```

## `mlx_slice_update_prod`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_slice_update_prod(a, update, lower, upper, [stride])
        a              type(mlx_array), intent(in) :: a
        update         type(mlx_array), intent(in) :: update
        lower          integer, intent(in) :: lower(:)
        upper          integer, intent(in) :: upper(:)
        stride         integer, optional, intent(in) :: stride(:)
        result         type(mlx_array) :: r
        ! a with its section lower:upper:stride multiplied by update
```

## `mlx_check_indices`

*Module* `mlxf_ops_index`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_check_indices
    subroutine mlx_check_indices(indices, extent, status)
        indices        type(mlx_array), intent(in) :: indices
        extent         integer, intent(in) :: extent
        status         integer, intent(out) :: status
        ! whether every value of indices, an integer array of any kind and shape, is a one-based index into extent: status 0 when 1 <= i <= extent for all of them (an empty array included), 1 otherwise, with the reason in mlx_last_error(). It evaluates the smallest and largest index once, a wait for the device: run it on untrusted input before the indices reach a graph, never inside a compiled or traced callback, and reuse the indices it accepted unchanged. Index 0, which the operations wrap to the last element, is refused here
    subroutine mlx_check_indices(indices, extent, size, status)
        indices        type(mlx_array), intent(in) :: indices
        extent         integer, intent(in) :: extent
        size           integer, intent(in) :: size
        status         integer, intent(out) :: status
        ! whether every value of indices is a one-based start of a slab of size elements inside extent: 1 <= i <= extent-size+1, after size is checked against extent (1 <= size <= extent); status as above
    subroutine mlx_check_indices(indices, extents, status)
        indices        type(mlx_array), intent(in) :: indices(:)
        extents        integer, intent(in) :: extents(:)
        status         integer, intent(out) :: status
        ! the element check of each array of a list against its own extent (the index arrays of mlx_gather and the scatters over a list of dimensions); the first failure is reported with its place in the list
    subroutine mlx_check_indices(indices, extents, sizes, status)
        indices        type(mlx_array), intent(in) :: indices(:)
        extents        integer, intent(in) :: extents(:)
        sizes          integer, intent(in) :: sizes(:)
        status         integer, intent(out) :: status
        ! the slab check of each array of a list against its own extent and slab size
```

## `matmul`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic matmul
    function matmul(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! Fortran's matmul(a, b), batched over dimensions 3 and up: in MLX's reversed view of the bytes this is matmul(b, a)
```

## `mlx_gather_mm`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_gather_mm(a, b, [lhs_indices], [rhs_indices], [sorted_indices])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        lhs_indices    type(mlx_array), optional, intent(in) :: lhs_indices
        rhs_indices    type(mlx_array), optional, intent(in) :: rhs_indices
        sorted_indices logical, optional, intent(in) :: sorted_indices
        result         type(mlx_array) :: r
        ! the products of chosen matrices: r(:,:,i) = matmul(a(:,:,lhs_indices(i)), b(:,:,rhs_indices(i))), the index arrays broadcast together and their shape following dimensions 1 and 2. An index is the 1-based number of a matrix in array element order over dimensions 3 and up; absent indices take every matrix of the operand
```

## `mlx_block_masked_mm`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_block_masked_mm(a, b, [block_size], [mask_out], [operand_masks])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        block_size     integer, optional, intent(in) :: block_size
        mask_out       type(mlx_array), optional, intent(in) :: mask_out
        operand_masks  type(mlx_array), optional, intent(in) :: operand_masks(2)
        result         type(mlx_array) :: r
        ! matmul(a, b) with blocks of block_size rows and columns (32 or 64; default 64) left out: mask_out(i, j) keeps or zeroes block (i, j) of the result, operand_masks(1) the blocks of a and operand_masks(2) those of b before the product. A mask is boolean (false zeroes), or real and multiplies its block
```

## `mlx_segmented_mm`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_segmented_mm(a, b, segments)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        segments       type(mlx_array), intent(in) :: segments
        result         type(mlx_array) :: r
        ! the product of two matrices cut along the inner dimension: r(:,:,i) = matmul(a(:, s1:s2), b(s1:s2, :)) with s1 = segments(1, i) and s2 = segments(2, i), inclusive and 1-based; an empty section gives zeros. The segments' dimensions 2 and up follow dimensions 1 and 2 of the result
```

## `mlx_addmm`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_addmm(c, a, b, [alpha], [beta])
        c              type(mlx_array), intent(in) :: c
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        alpha          real(real32), optional, intent(in) :: alpha
        beta           real(real32), optional, intent(in) :: beta
        result         type(mlx_array) :: r
        ! alpha*matmul(a, b) + beta*c in one node, c broadcast to the product; alpha and beta are 1 when absent. A rank-1 a is a row and a rank-1 b a column, as for Fortran's matmul
```

## `mlx_inner`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_inner(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! the sums of products over dimension 1 of both arrays, without conjugation: r(i..., j...) is the sum over k of a(k, i...)*b(k, j...), a's remaining dimensions before b's; with a scalar, the product
```

## `mlx_outer`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_outer(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! r(i, j) = a(i)*b(j) over the elements of a and of b in array element order: (size of a, size of b)
```

## `mlx_kron`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_kron(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! the Kronecker product: every element of a times the whole of b, r((i-1)*p + k, (j-1)*q + l) = a(i, j)*b(k, l) for a (p, q) matrix b; each extent is the product of the two, a lower rank padded with trailing extents of 1
```

## `mlx_vecdot`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_vecdot(a, b, [dim])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the dot products of the vectors along dimension dim (1 when absent) of two arrays of one rank, the first conjugated as Fortran's dot_product does; the other dimensions broadcast
```

## `mlx_cross`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_cross(a, b, [dim])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        dim            integer, optional, intent(in) :: dim
        result         type(mlx_array) :: r
        ! the cross products of the vectors of 3 (or 2, the third component zero) elements along dimension dim (1 when absent); the other dimensions broadcast
```

## `mlx_tensordot`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_tensordot
    function mlx_tensordot(a, b, [n])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        n              integer, optional, intent(in) :: n
        result         type(mlx_array) :: r
        ! the contraction of the last n dimensions of a with the first n of b, in order (n = 2 when absent; 1 is matmul for matrices, 0 the outer product): the remaining dimensions of a, then those of b
    function mlx_tensordot(a, b, dims_a, dims_b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        dims_a         integer, intent(in) :: dims_a(:)
        dims_b         integer, intent(in) :: dims_b(:)
        result         type(mlx_array) :: r
        ! the contraction of dimension dims_a(i) of a with dimension dims_b(i) of b for every i: the remaining dimensions of a, then those of b, each in its order
```

## `mlx_einsum`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_einsum(subscripts, operands)
        subscripts     character(len=*), intent(in) :: subscripts
        operands       type(mlx_array), intent(in) :: operands(:)
        result         type(mlx_array) :: r
        ! Einstein summation: in subscripts each operand has one letter per dimension, in Fortran's order, a repeated letter is summed over and '...' stands for the dimensions not named (they broadcast, aligned from the first). After '->' come the letters of the result; without it, the letters that occur once, capitals first and each case in alphabetical order, then the ellipsis
```

## `mlx_hadamard_transform`

*Module* `mlxf_linalg`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_hadamard_transform(a, [scale])
        a              type(mlx_array), intent(in) :: a
        scale          real(real32), optional, intent(in) :: scale
        result         type(mlx_array) :: r
        ! the Walsh-Hadamard transform along dimension 1, whose extent n is a power of two, times scale (1/sqrt(n) when absent, which makes the transform its own inverse)
```

## `mlx_inv`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_inv(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the inverse of every square matrix of a
```

## `mlx_pinv`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_pinv(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the Moore-Penrose pseudo-inverse of every (m, n) matrix of a: (n, m), from the singular values above a cut
```

## `mlx_tri_inv`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_tri_inv(a, [upper])
        a              type(mlx_array), intent(in) :: a
        upper          logical, optional, intent(in) :: upper
        result         type(mlx_array) :: r
        ! the inverse of every triangular matrix of a: lower triangular unless upper, the other triangle not read
```

## `mlx_det`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_det(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the determinant of every square matrix of a: the batch dimensions remain
```

## `mlx_slogdet`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_slogdet(a, sign, logabsdet)
        a              type(mlx_array), intent(in) :: a
        sign           type(mlx_array), intent(out) :: sign
        logabsdet      type(mlx_array), intent(out) :: logabsdet
        ! the determinant of every square matrix of a as its sign (-1, 0 or 1) and the logarithm of its magnitude
```

## `mlx_cholesky`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_cholesky(a, [upper])
        a              type(mlx_array), intent(in) :: a
        upper          logical, optional, intent(in) :: upper
        result         type(mlx_array) :: r
        ! the Cholesky factor of every symmetric positive definite matrix of a: the lower triangular l with a = matmul(l, transpose(l)), or with upper the upper triangular u with a = matmul(transpose(u), u)
```

## `mlx_cholesky_inv`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_cholesky_inv(factor, [upper])
        factor         type(mlx_array), intent(in) :: factor
        upper          logical, optional, intent(in) :: upper
        result         type(mlx_array) :: r
        ! the inverse of a symmetric positive definite matrix from its Cholesky factor, as mlx_cholesky returns it (lower triangular unless upper)
```

## `mlx_qr`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_qr(a, q, r)
        a              type(mlx_array), intent(in) :: a
        q              type(mlx_array), intent(out) :: q
        r              type(mlx_array), intent(out) :: r
        ! a = matmul(q, r) for every (m, n) matrix of a: q (m, k) with orthonormal columns and r (k, n) upper triangular, k the smaller of m and n
```

## `mlx_lu`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_lu(a, p, l, u)
        a              type(mlx_array), intent(in) :: a
        p              type(mlx_array), intent(out) :: p
        l              type(mlx_array), intent(out) :: l
        u              type(mlx_array), intent(out) :: u
        ! the LU factorisation with row pivoting of every (m, n) matrix of a: row i of a is row p(i) of matmul(l, u), with p a permutation of 1 to m (int32), l (m, k) unit lower triangular and u (k, n) upper triangular
```

## `mlx_lu_factor`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_lu_factor(a, lu, pivots)
        a              type(mlx_array), intent(in) :: a
        lu             type(mlx_array), intent(out) :: lu
        pivots         type(mlx_array), intent(out) :: pivots
        ! the LU factorisation as LAPACK packs it: lu holds u in its upper triangle and l below its diagonal (the unit diagonal left out), and row i was exchanged with row pivots(i), 1-based int32, for i = 1, 2, ... in turn
```

## `mlx_svd`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_svd
    subroutine mlx_svd(a, u, s, vt)
        a              type(mlx_array), intent(in) :: a
        u              type(mlx_array), intent(out) :: u
        s              type(mlx_array), intent(out) :: s
        vt             type(mlx_array), intent(out) :: vt
        ! a = matmul(u, matmul(diag(s), vt)) for every (m, n) matrix of a: u (m, m) and vt (n, n) orthogonal (unitary), s the singular values in descending order. MLX's factors of the transposed matrix are these, exchanged
    subroutine mlx_svd(a, s)
        a              type(mlx_array), intent(in) :: a
        s              type(mlx_array), intent(out) :: s
        ! the singular values alone, in descending order
```

## `mlx_eigh`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_eigh(a, w, v, [uplo])
        a              type(mlx_array), intent(in) :: a
        w              type(mlx_array), intent(out) :: w
        v              type(mlx_array), intent(out) :: v
        uplo           character(len=*), optional, intent(in) :: uplo
        ! the eigenvalues w, ascending, and the orthonormal eigenvectors (the columns of v) of every symmetric or Hermitian matrix of a: matmul(a, v(:, j)) = w(j)*v(:, j). Only the triangle uplo names is read ('L', the default, or 'U')
```

## `mlx_eigvalsh`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_eigvalsh(a, [uplo])
        a              type(mlx_array), intent(in) :: a
        uplo           character(len=*), optional, intent(in) :: uplo
        result         type(mlx_array) :: r
        ! the eigenvalues, ascending, of every symmetric or Hermitian matrix of a, from the triangle uplo names
```

## `mlx_eig`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    subroutine mlx_eig(a, w, v)
        a              type(mlx_array), intent(in) :: a
        w              type(mlx_array), intent(out) :: w
        v              type(mlx_array), intent(out) :: v
        ! the eigenvalues w and the right eigenvectors (the columns of v) of every square matrix of a, both complex: matmul(a, v(:, j)) = w(j)*v(:, j)
```

## `mlx_eigvals`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_eigvals(a)
        a              type(mlx_array), intent(in) :: a
        result         type(mlx_array) :: r
        ! the eigenvalues of every square matrix of a, complex, in the order mlx_eig returns them
```

## `mlx_solve`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_solve(a, b)
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        result         type(mlx_array) :: r
        ! x with matmul(a, x) = b for every square matrix of a: b is a vector (rank 1) or holds the right-hand sides as the columns of matrices (dimensions 1 and 2) with a's batch dimensions after them, and x has b's shape. MLX takes no batch of a against a single b, nor the reverse
```

## `mlx_solve_triangular`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_solve_triangular(a, b, [upper])
        a              type(mlx_array), intent(in) :: a
        b              type(mlx_array), intent(in) :: b
        upper          logical, optional, intent(in) :: upper
        result         type(mlx_array) :: r
        ! x with matmul(a, x) = b for every triangular matrix of a (lower triangular unless upper, the other triangle not read), b and x as for mlx_solve; here the batch dimensions of a and b broadcast
```

## `mlx_norm`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic mlx_norm
    function mlx_norm(a, ord, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        ord            real(c_double), intent(in) :: ord
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! the norm of order ord along dimension dim: the sum of |a|**ord to the power 1/ord, the largest (smallest) magnitude for an infinite (minus infinite) ord, the count of nonzeros for 0. Without dim, of a vector, or the matrix norm of a rank-2 array as the form with dims computes it
    function mlx_norm(a, ord, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        ord            real(c_double), intent(in) :: ord
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! over one dimension, the vector norm; over two, the matrix norm of the matrices whose rows run along dims(1) and columns along dims(2): the largest column sum of magnitudes for ord 1 (the smallest for -1), the largest row sum for an infinite ord, the largest (smallest) singular value for 2 (-2)
```

## `mlx_norm_matrix`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_norm_matrix(a, ord, [dims], [keepdims])
        a              type(mlx_array), intent(in) :: a
        ord            character(len=*), intent(in) :: ord
        dims           integer, optional, intent(in) :: dims(2)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! the matrix norm named ord of the matrices whose rows run along dims(1) and columns along dims(2), dimensions 1 and 2 when absent: 'fro', the root of the sum of squared magnitudes, or 'nuc', the sum of the singular values
```

## `norm2`

*Module* `mlxf_linalg_matrix`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
generic norm2
    function norm2(a, [dim], [keepdims])
        a              type(mlx_array), intent(in) :: a
        dim            integer, optional, intent(in) :: dim
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! the Euclidean norm along dimension dim, as Fortran's norm2 (of magnitudes for a complex array); without dim, of every element. A floating or complex array is scaled first (scaled_norm2), so that the norm of values near the ends of the kind's range is computed where it is representable; a float16 or bfloat16 one in float32 (mlxf_widened) and narrowed back, so that a long sum is accumulated where it is representable
    function norm2(a, dims, [keepdims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(:)
        keepdims       logical, optional, intent(in) :: keepdims
        result         type(mlx_array) :: r
        ! the Euclidean norm over one or two dimensions (the Frobenius norm of the matrices they span)
```

## `mlx_conv1d`

*Module* `mlxf_conv`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_conv1d(input, weight, [spec])
        input          type(mlx_array), intent(in) :: input
        weight         type(mlx_array), intent(in) :: weight
        spec           type(mlx_conv_spec), optional, intent(in) :: spec
        result         type(mlx_array) :: r
        ! the correlation of a (C, W, N) input with (C/groups, kW, C_out) kernels: element w' of the result's dimension 2 sums input(:, (w'-1)*stride - padding + (k-1)*dilation + 1, n)*weight(:, k, o) over the channels and k, where the input reaches (zeros outside); spec gives stride, padding, dilation and groups. A negative padding crops the input instead
```

## `mlx_conv2d`

*Module* `mlxf_conv`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_conv2d(input, weight, [spec])
        input          type(mlx_array), intent(in) :: input
        weight         type(mlx_array), intent(in) :: weight
        spec           type(mlx_conv_spec), optional, intent(in) :: spec
        result         type(mlx_array) :: r
        ! the same over two spatial dimensions: a (C, W, H, N) input and (C/groups, kW, kH, C_out) kernels
```

## `mlx_conv3d`

*Module* `mlxf_conv`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_conv3d(input, weight, [spec])
        input          type(mlx_array), intent(in) :: input
        weight         type(mlx_array), intent(in) :: weight
        spec           type(mlx_conv_spec), optional, intent(in) :: spec
        result         type(mlx_array) :: r
        ! the same over three spatial dimensions: a (C, W, H, D, N) input and (C/groups, kW, kH, kD, C_out) kernels; MLX takes one group only
```

## `mlx_conv_general`

*Module* `mlxf_conv`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_conv_general(input, weight, [spec])
        input          type(mlx_array), intent(in) :: input
        weight         type(mlx_array), intent(in) :: weight
        spec           type(mlx_conv_spec), optional, intent(in) :: spec
        result         type(mlx_array) :: r
        ! the general form over one to three spatial dimensions, by the rank of input: padding before and padding_hi (padding when absent) after each dimension, the input spread by input_dilation (zeros between its elements) and the kernels by dilation, groups, and with flip the kernels reversed along every spatial dimension
```

## `mlx_conv_transpose1d`

*Module* `mlxf_conv`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_conv_transpose1d(input, weight, [spec])
        input          type(mlx_array), intent(in) :: input
        weight         type(mlx_array), intent(in) :: weight
        spec           type(mlx_conv_spec), optional, intent(in) :: spec
        result         type(mlx_array) :: r
        ! the transposed convolution of a (C, W, N) input with (C/groups, kW, C_out) kernels: input element w adds input(:, w, n)*weight(:, k, o) to element (w-1)*stride - padding + (k-1)*dilation + 1 of the result's dimension 2, whose extent is (W-1)*stride - 2*padding + dilation*(kW-1) + 1 + output_padding. This holds for a padding up to dilation*(kW-1): beyond it MLX crops whole input elements and returns less
```

## `mlx_conv_transpose2d`

*Module* `mlxf_conv`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_conv_transpose2d(input, weight, [spec])
        input          type(mlx_array), intent(in) :: input
        weight         type(mlx_array), intent(in) :: weight
        spec           type(mlx_conv_spec), optional, intent(in) :: spec
        result         type(mlx_array) :: r
        ! the same over two spatial dimensions: a (C, W, H, N) input and (C/groups, kW, kH, C_out) kernels
```

## `mlx_conv_transpose3d`

*Module* `mlxf_conv`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_conv_transpose3d(input, weight, [spec])
        input          type(mlx_array), intent(in) :: input
        weight         type(mlx_array), intent(in) :: weight
        spec           type(mlx_conv_spec), optional, intent(in) :: spec
        result         type(mlx_array) :: r
        ! the same over three spatial dimensions: a (C, W, H, D, N) input and (C/groups, kW, kH, kD, C_out) kernels; MLX takes one group only
```

## `mlx_conv_spec`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
mlx_conv_spec (a derived type): the options of a convolution (mlx_conv1d to mlx_conv3d, mlx_conv_general, mlx_conv_transpose1d to 3d), one value per spatial dimension in Fortran order (dimension 2 of the input first). An absent list is the default (stride 1, padding 0, dilation 1, input dilation 1, output padding 0) and a list of one value serves every spatial dimension. padding pads both ends of the input of a convolution with zeros and takes as much from both ends of the result of a transposed one; mlx_conv_general alone pads the far end by padding_hi instead when it is present, spreads the input by input_dilation and reverses the kernel with flip. output_padding belongs to the transposed convolutions; groups is at least 1
    component  integer, allocatable :: stride(:), padding(:), dilation(:)
    component  integer, allocatable :: output_padding(:), padding_hi(:), input_dilation(:)
    component  integer :: groups = 1
    component  logical :: flip = .false.
```

## `mlx_fft`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_fft(a, dim, [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dim            integer, intent(in) :: dim
        n              integer, optional, intent(in) :: n
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the complex FFT along Fortran dimension dim; n pads or truncates (default: the extent), norm is one of MLX_FFT_NORMS (default backward: the forward transform is unscaled)
```

## `mlx_ifft`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_ifft(a, dim, [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dim            integer, intent(in) :: dim
        n              integer, optional, intent(in) :: n
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the inverse complex FFT along dim; the default backward norm scales it by 1/n
```

## `mlx_rfft`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_rfft(a, dim, [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dim            integer, intent(in) :: dim
        n              integer, optional, intent(in) :: n
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the FFT of a real array along dim, keeping the n/2+1 non-negative frequencies
```

## `mlx_irfft`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_irfft(a, dim, [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dim            integer, intent(in) :: dim
        n              integer, optional, intent(in) :: n
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the inverse of mlx_rfft along dim; the default length is 2*(extent-1), so an odd length needs n
```

## `mlx_fft2`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_fft2(a, dims, [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(2)
        n              integer, optional, intent(in) :: n(2)
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the complex FFT over the two Fortran dimensions dims, every other dimension a batch; n per dimension
```

## `mlx_ifft2`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_ifft2(a, dims, [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(2)
        n              integer, optional, intent(in) :: n(2)
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the inverse of mlx_fft2 over dims
```

## `mlx_fftn`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_fftn(a, [dims], [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dims           integer, optional, intent(in) :: dims(:)
        n              integer, optional, intent(in) :: n(:)
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the complex FFT over the Fortran dimensions dims (absent: every dimension), the others batches; n gives the length along each transformed dimension, in dims' order (absent: the extents)
```

## `mlx_ifftn`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_ifftn(a, [dims], [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dims           integer, optional, intent(in) :: dims(:)
        n              integer, optional, intent(in) :: n(:)
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the inverse of mlx_fftn over dims; the default backward norm scales it by one over the product of the lengths
```

## `mlx_rfft2`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_rfft2(a, dims, [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(2)
        n              integer, optional, intent(in) :: n(2)
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the FFT of a real array over the two Fortran dimensions dims: the result keeps the n(1)/2+1 non-negative frequencies along dims(1), the half-size dimension, and every frequency along dims(2)
```

## `mlx_irfft2`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_irfft2(a, dims, [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dims           integer, intent(in) :: dims(2)
        n              integer, optional, intent(in) :: n(2)
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the inverse of mlx_rfft2: a real array of lengths n along dims, from a spectrum that is half along dims(1); the default length along dims(1) is 2*(extent-1), so an odd length needs n
```

## `mlx_rfftn`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_rfftn(a, [dims], [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dims           integer, optional, intent(in) :: dims(:)
        n              integer, optional, intent(in) :: n(:)
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the FFT of a real array over the Fortran dimensions dims (absent: every dimension): the result keeps the n/2+1 non-negative frequencies along dims(1), the half-size dimension (dimension 1 when dims is absent)
```

## `mlx_irfftn`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_irfftn(a, [dims], [n], [norm])
        a              type(mlx_array), intent(in) :: a
        dims           integer, optional, intent(in) :: dims(:)
        n              integer, optional, intent(in) :: n(:)
        norm           integer, optional, intent(in) :: norm
        result         type(mlx_array) :: r
        ! the inverse of mlx_rfftn: a real array of lengths n along dims, from a spectrum that is half along dims(1); the default length along dims(1) is 2*(extent-1), so an odd length needs n
```

## `mlx_fftshift`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_fftshift(a, [dims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, optional, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! a with the zero frequency moved to the centre of each listed dimension (absent: every dimension), element extent/2 + 1: a circular shift by extent/2 towards higher indices
```

## `mlx_ifftshift`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_ifftshift(a, [dims])
        a              type(mlx_array), intent(in) :: a
        dims           integer, optional, intent(in) :: dims(:)
        result         type(mlx_array) :: r
        ! the inverse of mlx_fftshift: a circular shift by extent/2 towards lower indices, which differs from mlx_fftshift along a dimension of odd extent
```

## `mlx_fftfreq`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_fftfreq(n, [d])
        n              integer, intent(in) :: n
        d              real(real64), optional, intent(in) :: d
        result         type(mlx_array) :: r
        ! the frequencies of the n elements of a transform, in its order (0, 1, ..., then the negative ones), in cycles per unit of the sample spacing d (default 1): float32, rank 1
```

## `mlx_rfftfreq`

*Module* `mlxf_fft`; *contract:* [10. Operations, matrices and Fourier transforms](policies/binding_contract_policy.md#10-operations-matrices-and-fourier-transforms)

```text
    function mlx_rfftfreq(n, [d])
        n              integer, intent(in) :: n
        d              real(real64), optional, intent(in) :: d
        result         type(mlx_array) :: r
        ! the n/2+1 non-negative frequencies of a real transform of n samples spaced d apart (default 1): float32
```

## `MLX_FFT_NORMS`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
MLX_FFT_NORMS (a named constant)
    type(mlx_fft_norm_codes), parameter :: MLX_FFT_NORMS = mlx_fft_norm_codes()
    codes:
        component  integer :: backward = int(MLXC_FFT_NORM_BACKWARD)
        component  integer :: ortho = int(MLXC_FFT_NORM_ORTHO)
        component  integer :: forward = int(MLXC_FFT_NORM_FORWARD)
```

## `mlx_function`

*Module* `mlxf_compile`; *contract:* [11. Fortran callbacks and graph compilation](policies/binding_contract_policy.md#11-fortran-callbacks-and-graph-compilation)

```text
generic mlx_function
    function mlx_function(callback)
        callback       procedure(array_callback) :: callback
        result         type(mlx_function) :: f
        ! an mlx_function from a checked subroutine callback(inputs, outputs, status)
```

## `mlx_compile`

*Module* `mlxf_compile`; *contract:* [11. Fortran callbacks and graph compilation](policies/binding_contract_policy.md#11-fortran-callbacks-and-graph-compilation)

```text
    function mlx_compile(f, [shapeless])
        f              type(mlx_function), intent(in) :: f
        shapeless      logical, optional, intent(in) :: shapeless
        result         type(mlx_function) :: g
        ! the compiled form of f, shapeless keeping one trace across input shapes; it shares f's payload, which MLX keeps alive after f is killed
```

## `mlx_enable_compile`

*Module* `mlxf_compile`; *contract:* [11. Fortran callbacks and graph compilation](policies/binding_contract_policy.md#11-fortran-callbacks-and-graph-compilation)

```text
    subroutine mlx_enable_compile()
        ! compilation on, for the functions compiled from now on (MLX's default)
```

## `mlx_disable_compile`

*Module* `mlxf_compile`; *contract:* [11. Fortran callbacks and graph compilation](policies/binding_contract_policy.md#11-fortran-callbacks-and-graph-compilation)

```text
    subroutine mlx_disable_compile()
        ! compilation off: a function compiled from now on runs its callback at every call, and stays so
```

## `mlx_set_compile_mode`

*Module* `mlxf_compile`; *contract:* [11. Fortran callbacks and graph compilation](policies/binding_contract_policy.md#11-fortran-callbacks-and-graph-compilation)

```text
    subroutine mlx_set_compile_mode(mode)
        mode           integer, intent(in) :: mode
        ! what compilation does: a member of MLX_COMPILE_MODES (another value stops)
```

## `MLX_COMPILE_MODES`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
MLX_COMPILE_MODES (a named constant)
    type(mlx_compile_mode_codes), parameter :: MLX_COMPILE_MODES = mlx_compile_mode_codes()
    codes:
        component  integer :: disabled = int(MLXC_COMPILE_MODE_DISABLED)
        component  integer :: no_simplify = int(MLXC_COMPILE_MODE_NO_SIMPLIFY)
        component  integer :: no_fuse = int(MLXC_COMPILE_MODE_NO_FUSE)
        component  integer :: enabled = int(MLXC_COMPILE_MODE_ENABLED)
```

## `mlx_grad_function`

*Module* `mlxf_transforms`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
mlx_grad_function (a derived type)
    %new, bound to grad_function_new:
        subroutine new(self, f, [argnums])
            self           class(mlx_grad_function), intent(inout) :: self
            f              type(mlx_function), intent(in) :: f
            argnums        integer, optional, intent(in) :: argnums(:)
    %kill, bound to grad_function_kill:
        subroutine kill(self)
            self           class(mlx_grad_function), intent(inout) :: self
    %apply, bound to grad_function_apply:
        subroutine apply(self, inputs, values, grads, [status])
            self           class(mlx_grad_function), intent(in) :: self
            inputs         type(mlx_array), intent(in) :: inputs(:)
            values         type(mlx_array), allocatable, intent(out) :: values(:)
            grads          type(mlx_array), allocatable, intent(out) :: grads(:)
            status         integer, optional, intent(out) :: status
    assignment(=), for these operand pairs:
        class(mlx_grad_function), intent(inout), class(mlx_grad_function)
```

## `mlx_value_and_grad`

*Module* `mlxf_transforms`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
    function mlx_value_and_grad(f, [argnums])
        f              type(mlx_function), intent(in) :: f
        argnums        integer, optional, intent(in) :: argnums(:)
        result         type(mlx_grad_function) :: g
        ! the function that returns f's outputs and the gradients of its first output, a scalar, with respect to the inputs at the one-based positions argnums (the first input by default)
```

## `mlx_vjp`

*Module* `mlxf_transforms`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
    subroutine mlx_vjp(f, primals, cotangents, outputs, vjps)
        f              type(mlx_function), intent(in) :: f
        primals        type(mlx_array), intent(in) :: primals(:)
        cotangents     type(mlx_array), intent(in) :: cotangents(:)
        outputs        type(mlx_array), allocatable, intent(out) :: outputs(:)
        vjps           type(mlx_array), allocatable, intent(out) :: vjps(:)
        ! f's outputs on primals and, for the cotangents (one per output, of its shape), the products of the transposed Jacobian with them: one array per input, of its shape. A failure, the callback's included, stops. Recursive: the callback may itself take a product, for a derivative of a derivative
```

## `mlx_jvp`

*Module* `mlxf_transforms`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
    subroutine mlx_jvp(f, primals, tangents, outputs, jvps)
        f              type(mlx_function), intent(in) :: f
        primals        type(mlx_array), intent(in) :: primals(:)
        tangents       type(mlx_array), intent(in) :: tangents(:)
        outputs        type(mlx_array), allocatable, intent(out) :: outputs(:)
        jvps           type(mlx_array), allocatable, intent(out) :: jvps(:)
        ! f's outputs on primals and, for the tangents (one per input, of its shape), the products of the Jacobian with them: one array per output, of its shape. A failure, the callback's included, stops. Recursive, as mlx_vjp is
```

## `mlx_custom_vjp`

*Module* `mlxf_transforms`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
    function mlx_custom_vjp(f, vjp)
        f              type(mlx_function), intent(in) :: f
        vjp            procedure(vjp_callback) :: vjp
        result         type(mlx_function) :: g
        ! f with its vector-Jacobian product replaced by vjp, a checked subroutine (primals, cotangents, outputs, vjps, status); the values of f are unchanged
```

## `mlx_custom_function`

*Module* `mlxf_transforms`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
    function mlx_custom_function(f, [vjp], [jvp])
        f              type(mlx_function), intent(in) :: f
        vjp            procedure(vjp_callback), optional :: vjp
        jvp            procedure(jvp_callback), optional :: jvp
        result         type(mlx_function) :: g
        ! f with its vector-Jacobian product replaced by vjp and its Jacobian-vector product by jvp, a checked subroutine (primals, tangents, argnums, jvps, status); an absent one stays MLX's own
```

## `mlx_checkpoint`

*Module* `mlxf_transforms`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
    function mlx_checkpoint(f)
        f              type(mlx_function), intent(in) :: f
        result         type(mlx_function) :: g
        ! f with the intermediate arrays of its gradient discarded and recomputed when the gradient is taken
```

## `mlx_depends`

*Module* `mlxf_transforms`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
    subroutine mlx_depends(inputs, dependencies, outputs)
        inputs         type(mlx_array), intent(in) :: inputs(:)
        dependencies   type(mlx_array), intent(in) :: dependencies(:)
        outputs        type(mlx_array), allocatable, intent(out) :: outputs(:)
        ! the inputs as arrays whose evaluation also evaluates the dependencies: outputs(i) has the values of inputs(i). An empty list of inputs stops: MLX reads the first one unchecked
```

## `mlx_export_function`

*Module* `mlxf_export`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
    subroutine mlx_export_function(file, f, inputs, [shapeless], [status])
        file           character(len=*), intent(in) :: file
        f              type(mlx_function), intent(in) :: f
        inputs         type(mlx_array), intent(in) :: inputs(:)
        shapeless      logical, optional, intent(in) :: shapeless
        status         integer, optional, intent(out) :: status
        ! writes to file the graph f builds on inputs; with shapeless the graph serves other extents of the same ranks and dtypes. With status, a failure (the callback's, or the file's) returns with MLX usable
```

## `mlx_function_exporter`

*Module* `mlxf_export`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
generic mlx_function_exporter
    function mlx_function_exporter(file, f, [shapeless])
        file           character(len=*), intent(in) :: file
        f              type(mlx_function), intent(in) :: f
        shapeless      logical, optional, intent(in) :: shapeless
        result         type(mlx_function_exporter) :: e
        ! an exporter that writes to file one trace of f for each application
```

## `mlx_imported_function`

*Module* `mlxf_export`; *contract:* [14. Function transforms, functions in files, compilation controls](policies/binding_contract_policy.md#14-function-transforms-functions-in-files-compilation-controls)

```text
generic mlx_imported_function
    function mlx_imported_function(file)
        file           character(len=*), intent(in) :: file
        result         type(mlx_imported_function) :: g
        ! the function a file holds; a file that cannot be read stops (the binding new takes a status)
```

## `mlx_custom_kernel`

*Module* `mlxf_fast`; *contract:* [15. Fused layers](policies/binding_contract_policy.md#15-fused-layers)

```text
generic mlx_custom_kernel
    function mlx_custom_kernel(spec)
        spec           type(mlx_custom_kernel_spec), intent(in) :: spec
        result         type(mlx_custom_kernel) :: k
        ! the kernel a spec describes
```

## `mlx_custom_kernel_spec`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
mlx_custom_kernel_spec (a derived type): a custom kernel and its launch (mlx_custom_kernel) for MLX's Metal or CUDA backend: the body of the Metal function (source) and of the CUDA function (cuda_source), declarations put before either (header; CUDA compiles it with NVRTC, where a plain function is device code), the names its buffers take in the sources, the thread grid and the threadgroup as (x, y, z) (CUDA launches whole blocks of the threadgroup, so a CUDA source guards its index), the dynamic shared memory of a CUDA launch in bytes, and the outputs. output_shapes holds the outputs' Fortran shapes one after another and output_ranks how many extents each takes (absent: the outputs share them equally); absent output_dtypes are float32. A template parameter is a name with a dtype, an integer or a logical. With init_value every output is filled with it before the kernel runs (atomic_outputs is Metal's; a CUDA source adds atomically to a plain output). The sources index MLX's buffers, row-major and 0-based
    component  character(len=:), allocatable :: name, source, cuda_source, header
    component  character(len=:), allocatable :: input_names(:), output_names(:)
    component  integer :: grid(3) = [1, 1, 1], threadgroup(3) = [1, 1, 1], shared_memory = 0
    component  integer, allocatable :: output_shapes(:), output_ranks(:), output_dtypes(:)
    component  character(len=:), allocatable :: template_dtype_names(:), template_int_names(:), template_bool_names(:)
    component  integer, allocatable :: template_dtypes(:), template_ints(:)
    component  logical, allocatable :: template_bools(:)
    component  real(c_float), allocatable :: init_value
    component  logical :: ensure_row_contiguous = .true., atomic_outputs = .false., verbose = .false.
```

## `mlx_layer_norm`

*Module* `mlxf_fast`; *contract:* [15. Fused layers](policies/binding_contract_policy.md#15-fused-layers)

```text
    function mlx_layer_norm(x, [weight], [bias], [eps])
        x              type(mlx_array), intent(in) :: x
        weight         type(mlx_array), optional, intent(in) :: weight
        bias           type(mlx_array), optional, intent(in) :: bias
        eps            real(real32), optional, intent(in) :: eps
        result         type(mlx_array) :: r
        ! x normalised along dimension 1: (x - mean)/sqrt(variance + eps), the mean and the variance (divided by the extent) taken over dimension 1, then times weight and plus bias, rank-1 arrays of that extent, when given
```

## `mlx_rms_norm`

*Module* `mlxf_fast`; *contract:* [15. Fused layers](policies/binding_contract_policy.md#15-fused-layers)

```text
    function mlx_rms_norm(x, [weight], [eps])
        x              type(mlx_array), intent(in) :: x
        weight         type(mlx_array), optional, intent(in) :: weight
        eps            real(real32), optional, intent(in) :: eps
        result         type(mlx_array) :: r
        ! x divided by its root mean square along dimension 1, sqrt(mean(x**2) + eps), then times weight, a rank-1 array of that extent, when given
```

## `mlx_rope`

*Module* `mlxf_fast`; *contract:* [15. Fused layers](policies/binding_contract_policy.md#15-fused-layers)

```text
    function mlx_rope(x, [spec], [offset], [freqs])
        x              type(mlx_array), intent(in) :: x
        spec           type(mlx_rope_spec), optional, intent(in) :: spec
        offset         type(mlx_array), optional, intent(in) :: offset
        freqs          type(mlx_array), optional, intent(in) :: freqs
        result         type(mlx_array) :: r
        ! the rotary position embedding of x (features, positions, ...): a pair (x1, x2) of elements along dimension 1 becomes (x1 cos - x2 sin, x1 sin + x2 cos) of the angle (position - 1 + offset) scale / divisor(pair), the position counted along dimension 2. offset, an integer array (rank 0, or rank 1 with one value per element of the last dimension), replaces spec%offset; freqs, one divisor per pair, replaces those of the base
```

## `mlx_rope_spec`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
mlx_rope_spec (a derived type): the options of a rotary position embedding (mlx_rope): how many elements of dimension 1 are rotated, from the first (even; 0: all of them); traditional pairs neighbours (1, 2), (3, 4), ..., otherwise element p goes with element p + features/2; the base of the divisors of the angle, base**((p-1)/(features/2)) for pair p, used when none are given; the scale of the positions; and the number of positions before the first
    component  integer :: features = 0
    component  logical :: traditional = .false.
    component  real(c_float) :: base = 10000._c_float
    component  real(c_float) :: scale = 1._c_float
    component  integer :: offset = 0
```

## `mlx_scaled_dot_product_attention`

*Module* `mlxf_fast`; *contract:* [15. Fused layers](policies/binding_contract_policy.md#15-fused-layers)

```text
    function mlx_scaled_dot_product_attention(queries, keys, values, [spec], [mask])
        queries        type(mlx_array), intent(in) :: queries
        keys           type(mlx_array), intent(in) :: keys
        values         type(mlx_array), intent(in) :: values
        spec           type(mlx_attention_spec), optional, intent(in) :: spec
        mask           type(mlx_array), optional, intent(in) :: mask
        result         type(mlx_array) :: r
        ! attention: for queries (d, lq, heads, batch), keys (d, lk, heads, batch) and values (dv, lk, heads, batch), r(:, i, h, b) is the sum over the keys j of softmax_j(scale * dot(q(:, i), k(:, j))) * v(:, j). A boolean mask(j, i, ...) keeps key j for query i, a real one is added to the scores; it broadcasts to (lk, lq, heads, batch)
```

## `mlx_attention_spec`

*Module* `mlxf_defs`; *contract:* [5. Kinds and scalars](policies/binding_contract_policy.md#5-kinds-and-scalars)

```text
mlx_attention_spec (a derived type): the options of mlx_scaled_dot_product_attention: the factor of the scores (not set: one over the square root of the queries' first extent), whether a query attends only the keys up to its own position, and whether MLX's fused kernel is demanded (it then stops where it has none)
    component  real(c_float), allocatable :: scale
    component  logical :: causal = .false.
    component  logical :: force_fused = .false.
```

## `mlx_cross_entropy`

*Module* `mlxf_fast`; *contract:* [15. Fused layers](policies/binding_contract_policy.md#15-fused-layers)

```text
    function mlx_cross_entropy(logits, targets)
        logits         type(mlx_array), intent(in) :: logits
        targets        type(mlx_array), intent(in) :: targets
        result         type(mlx_array) :: r
        ! the cross entropy of logits (classes, ...) against targets (...), one-based integer classes: for each distribution along dimension 1, log(sum(exp(logits))) - logits(target), float32
```

## `mlx_random_seed`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
generic mlx_random_seed
    subroutine mlx_random_seed(seed)
        seed           integer(int32), intent(in) :: seed
        ! sets MLX's global key, which the samplers called without a key draw from and advance
    subroutine mlx_random_seed(seed)
        seed           integer(int64), intent(in) :: seed
        ! the same from a 64-bit seed, whose bits MLX reads as an unsigned integer
```

## `mlx_random_key`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
generic mlx_random_key
    function mlx_random_key(seed)
        seed           integer(int32), intent(in) :: seed
        result         type(mlx_array) :: key
        ! the key of a seed: a uint32 array of two elements, the seed's high and low 32 bits
    function mlx_random_key(seed)
        seed           integer(int64), intent(in) :: seed
        result         type(mlx_array) :: key
```

## `mlx_random_split`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
generic mlx_random_split
    subroutine mlx_random_split(key, first, second)
        key            type(mlx_array), intent(in) :: key
        first          type(mlx_array), intent(out) :: first
        second         type(mlx_array), intent(out) :: second
        ! two new keys from key, independent of it and of each other
    subroutine mlx_random_split(key, num, keys)
        key            type(mlx_array), intent(in) :: key
        num            integer, intent(in) :: num
        keys           type(mlx_array), intent(out) :: keys
        ! num new keys from key as one uint32 array of shape (2, num): key i is keys(:, i)
```

## `mlx_random_bits`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_bits(shape, [width], [key])
        shape          integer, intent(in) :: shape(:)
        width          integer, optional, intent(in) :: width
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! random bits as unsigned integers of width bytes (1, 2 or 4, the default: uint8, uint16 or uint32)
```

## `mlx_random_uniform`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_uniform(shape, [low], [high], [dtype], [key])
        shape          integer, intent(in) :: shape(:)
        low            type(mlx_array), optional, intent(in) :: low
        high           type(mlx_array), optional, intent(in) :: high
        dtype          integer, optional, intent(in) :: dtype
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! uniform samples in [low, high): the bounds are arrays that broadcast to shape, 0 and 1 by default
```

## `mlx_random_normal`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
generic mlx_random_normal
    function mlx_random_normal(shape, [loc], [scale], [dtype], [key])
        shape          integer, intent(in) :: shape(:)
        loc            real(real32), optional, intent(in) :: loc
        scale          real(real32), optional, intent(in) :: scale
        dtype          integer, optional, intent(in) :: dtype
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! normal samples of mean loc and standard deviation scale, 0 and 1 by default
    function mlx_random_normal(shape, loc, [scale], [dtype], [key])
        shape          integer, intent(in) :: shape(:)
        loc            type(mlx_array), intent(in) :: loc
        scale          type(mlx_array), optional, intent(in) :: scale
        dtype          integer, optional, intent(in) :: dtype
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! normal samples whose mean and standard deviation are arrays that broadcast to shape; scale is 1 by default. An empty handle would reach MLX as an absent parameter, so both are checked here; and MLX does not hold these two to shape, as it holds the parameters of the other samplers, so the result's shape is checked
```

## `mlx_random_laplace`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_laplace(shape, [loc], [scale], [dtype], [key])
        shape          integer, intent(in) :: shape(:)
        loc            real(real32), optional, intent(in) :: loc
        scale          real(real32), optional, intent(in) :: scale
        dtype          integer, optional, intent(in) :: dtype
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! Laplace samples of mean loc and scale parameter scale (the variance is 2 scale**2), 0 and 1 by default
```

## `mlx_random_gumbel`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_gumbel(shape, [dtype], [key])
        shape          integer, intent(in) :: shape(:)
        dtype          integer, optional, intent(in) :: dtype
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! samples of the standard Gumbel distribution
```

## `mlx_random_truncated_normal`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_truncated_normal(shape, lower, upper, [dtype], [key])
        shape          integer, intent(in) :: shape(:)
        lower          type(mlx_array), intent(in) :: lower
        upper          type(mlx_array), intent(in) :: upper
        dtype          integer, optional, intent(in) :: dtype
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! standard normal samples kept inside [lower, upper], arrays that broadcast to shape
```

## `mlx_random_randint`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_randint(shape, low, high, [dtype], [key])
        shape          integer, intent(in) :: shape(:)
        low            type(mlx_array), intent(in) :: low
        high           type(mlx_array), intent(in) :: high
        dtype          integer, optional, intent(in) :: dtype
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! integers drawn uniformly from low to high - 1, arrays that broadcast to shape; int32 by default
```

## `mlx_random_bernoulli`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_bernoulli(shape, p, [key])
        shape          integer, intent(in) :: shape(:)
        p              type(mlx_array), intent(in) :: p
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! booleans that are true with probability p, a real array that broadcasts to shape
```

## `mlx_random_multivariate_normal`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_multivariate_normal(mean, cov, [shape], [dtype], [key])
        mean           type(mlx_array), intent(in) :: mean
        cov            type(mlx_array), intent(in) :: cov
        shape          integer, optional, intent(in) :: shape(:)
        dtype          integer, optional, intent(in) :: dtype
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! vectors along dimension 1 drawn from the normal distribution of mean (n, ...) and covariance cov (n, n, ...); shape is the shape of the batch of vectors, the result (n, shape) broadcast with the batches of mean and cov. MLX takes the root of cov by a singular value decomposition, so the whole draw runs on the CPU's stream
```

## `mlx_random_categorical`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
    function mlx_random_categorical(logits, [dim], [num_samples], [shape], [key])
        logits         type(mlx_array), intent(in) :: logits
        dim            integer, optional, intent(in) :: dim
        num_samples    integer, optional, intent(in) :: num_samples
        shape          integer, optional, intent(in) :: shape(:)
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! one-based int32 categories drawn with the unnormalised log-probabilities logits holds along dim (1 by default): one per distribution, the result having logits' other dimensions; with num_samples that many per distribution, along a new first dimension; with shape a sample of that Fortran shape, which the other dimensions of logits broadcast to
```

## `mlx_random_permutation`

*Module* `mlxf_random`; *contract:* [13. Random numbers](policies/binding_contract_policy.md#13-random-numbers)

```text
generic mlx_random_permutation
    function mlx_random_permutation(x, [dim], [key])
        x              type(mlx_array), intent(in) :: x
        dim            integer, optional, intent(in) :: dim
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! x with its slices along dim in a random order (the last dimension by default, MLX's first axis)
    function mlx_random_permutation(n, [key])
        n              integer, intent(in) :: n
        key            type(mlx_array), optional, intent(in) :: key
        result         type(mlx_array) :: r
        ! a random permutation of 1 to n, int32
```
