/* src/test/mlxf_abi_probe.c -- the ABI probe's echo functions (src/test/mlxf_abi_probe.h), compiled by Apple's
 * clang, the compiler of mlx-c, into an object of mlxf_test_exec (test/CMakeLists.txt). The struct and enumerator
 * tables are written here from mlx-c's headers with C's own sizeof, _Alignof and offsetof, independently of the
 * generator; a name the generated layer has and these tables lack makes the probe fail until it is added.
 */
#include <string.h>
#include "mlxf_abi_probe.h"

int mlx_abiprobe_int(int* res, int v) { *res = v; return 0; }
int mlx_abiprobe_bool(bool* res, bool v) { *res = v; return 0; }
int mlx_abiprobe_float(float* res, float v) { *res = v; return 0; }
int mlx_abiprobe_double(double* res, double v) { *res = v; return 0; }
int mlx_abiprobe_size(size_t* res, size_t v) { *res = v; return 0; }
int mlx_abiprobe_uint64(uint64_t* res, uint64_t v) { *res = v; return 0; }
int mlx_abiprobe_uintptr(void** res, uintptr_t v) { *res = (void*)v; return 0; }
int mlx_abiprobe_dtype(mlx_dtype* res, mlx_dtype v) { *res = v; return 0; }

int mlx_abiprobe_optional_int(mlx_optional_int* res, mlx_optional_int v) { *res = v; return 0; }
int mlx_abiprobe_optional_float(mlx_optional_float* res, mlx_optional_float v) { *res = v; return 0; }
int mlx_abiprobe_optional_dtype(mlx_optional_dtype* res, mlx_optional_dtype v) { *res = v; return 0; }

int mlx_abiprobe_stack(
    int* ri, bool* rb, float* rf, double* rd,
    int f1, int f2, int f3, int f4,
    double g1, double g2, double g3, double g4, double g5, double g6, double g7, double g8,
    bool b, int i, float f, double d) {
  if (f1 != 1 || f2 != 2 || f3 != 3 || f4 != 4) return 1;
  if (g1 != 1.5 || g2 != 2.5 || g3 != 3.5 || g4 != 4.5 || g5 != 5.5 || g6 != 6.5 || g7 != 7.5 || g8 != 8.5)
    return 2;
  *ri = i;
  *rb = b;
  *rf = f;
  *rd = d;
  return 0;
}

int mlx_abiprobe_stack_optional(
    mlx_optional_int* roi, mlx_optional_float* rof, mlx_optional_dtype* rod,
    int f1, int f2, int f3, int f4, int f5,
    mlx_optional_int oi, mlx_optional_float of, mlx_optional_dtype od) {
  if (f1 != 1 || f2 != 2 || f3 != 3 || f4 != 4 || f5 != 5) return 1;
  *roi = oi;
  *rof = of;
  *rod = od;
  return 0;
}

int mlx_abiprobe_refs(
    int8_t* a, int16_t* b, int32_t* c, int64_t* d, float* e, double* f, mlx_complex64_t* g) {
  *a *= 2;
  *b *= 2;
  *c *= 2;
  *d *= 2;
  *e *= 2;
  *f *= 2;
  *g *= 2;
  return 0;
}

int mlx_abiprobe_urefs(uint8_t* a, uint16_t* b, uint32_t* c, uint64_t* d) {
  *a *= 2;
  *b *= 2;
  *c *= 2;
  *d *= 2;
  return 0;
}

int mlx_abiprobe_int_array(int* res, const int* a, size_t n) {
  int s = 0;
  for (size_t k = 0; k < n; ++k) s += (int)(k + 1) * a[k];
  *res = s;
  return 0;
}

int mlx_abiprobe_int64_arrays(int64_t* res, const int64_t* a, const uint64_t* b, size_t n) {
  int64_t s = 0;
  for (size_t k = 0; k < n; ++k) s += (int64_t)(k + 1) * a[k] + (int64_t)(k + 1) * (int64_t)b[k];
  *res = s;
  return 0;
}

mlx_array mlx_abiprobe_handle(const mlx_array a) { return a; }
int mlx_abiprobe_handle_ref(mlx_array* res, const mlx_array a) { *res = a; return 0; }

int mlx_abiprobe_handles(mlx_array* res, const mlx_array* arr, size_t num) {
  if (num == 0) return 1;
  *res = arr[num - 1];
  return 0;
}

mlx_map_string_to_array_iterator mlx_abiprobe_iterator(void* ctx, void* map_ctx) {
  mlx_map_string_to_array_iterator it;
  it.ctx = ctx;
  it.map_ctx = map_ctx;
  return it;
}

int mlx_abiprobe_iterator_echo(void** ctx, void** map_ctx, mlx_map_string_to_array_iterator it) {
  *ctx = it.ctx;
  *map_ctx = it.map_ctx;
  return 0;
}

void* mlx_abiprobe_pointer(void* p) { return p; }
int mlx_abiprobe_pointer_ref(void** res, void* p) { *res = p; return 0; }
int mlx_abiprobe_file(void** res, FILE* f) { *res = (void*)f; return 0; }
int mlx_abiprobe_strlen(size_t* res, const char* s) { *res = strlen(s); return 0; }

int mlx_abiprobe_string(const char** res, int which) {
  *res = which == 1 ? "abi probe" : "other";
  return 0;
}

int mlx_abiprobe_chars(char** res, void* s) { *res = (char*)s + 4; return 0; }

int mlx_abiprobe_funptr(int* res, int (*fun)(int), int v) { *res = fun(v); return 0; }

int mlx_abiprobe_int_result(int v) { return v; }
size_t mlx_abiprobe_size_result(size_t v) { return v + 1; }
bool mlx_abiprobe_bool_result(bool v) { return !v; }
void mlx_abiprobe_void(int* res, int v) { *res = v + 1; }

/* ---- the layouts ------------------------------------------------------------------------------------------ */

#define FIELD(T, F) sizeof(((T*)0)->F)
#define HANDLE(T) {#T, sizeof(T), _Alignof(T), offsetof(T, ctx), 0, FIELD(T, ctx), 0}
#define PAIR(T, A, B) {#T, sizeof(T), _Alignof(T), offsetof(T, A), offsetof(T, B), FIELD(T, A), FIELD(T, B)}

struct layout {
  const char* name;
  size_t size, align, offset1, offset2, size1, size2;
};

static const struct layout LAYOUTS[] = {
    HANDLE(mlx_array),
    HANDLE(mlx_closure),
    HANDLE(mlx_closure_custom),
    HANDLE(mlx_closure_custom_jvp),
    HANDLE(mlx_closure_custom_vmap),
    HANDLE(mlx_closure_kwargs),
    HANDLE(mlx_closure_value_and_grad),
    HANDLE(mlx_compile_cache),
    HANDLE(mlx_device),
    HANDLE(mlx_device_info),
    HANDLE(mlx_distributed_group),
    HANDLE(mlx_fast_cuda_kernel),
    HANDLE(mlx_fast_cuda_kernel_config),
    HANDLE(mlx_fast_metal_kernel),
    HANDLE(mlx_fast_metal_kernel_config),
    HANDLE(mlx_function_exporter),
    HANDLE(mlx_imported_function),
    HANDLE(mlx_io_gguf),
    HANDLE(mlx_io_reader),
    HANDLE(mlx_io_writer),
    HANDLE(mlx_map_string_to_array),
    HANDLE(mlx_map_string_to_string),
    HANDLE(mlx_node_namer),
    HANDLE(mlx_stream),
    HANDLE(mlx_stream_thread_local),
    HANDLE(mlx_string),
    HANDLE(mlx_vector_array),
    HANDLE(mlx_vector_int),
    HANDLE(mlx_vector_stream),
    HANDLE(mlx_vector_string),
    HANDLE(mlx_vector_vector_array),
    PAIR(mlx_map_string_to_array_iterator, ctx, map_ctx),
    PAIR(mlx_map_string_to_string_iterator, ctx, map_ctx),
    PAIR(mlx_optional_dtype, value, has_value),
    PAIR(mlx_optional_float, value, has_value),
    PAIR(mlx_optional_int, value, has_value),
};

#define ENUMERATOR(E) {#E, E}

struct enumerator {
  const char* name;
  int value;
};

static const struct enumerator ENUMERATORS[] = {
    ENUMERATOR(MLX_COMPILE_MODE_DISABLED),
    ENUMERATOR(MLX_COMPILE_MODE_NO_SIMPLIFY),
    ENUMERATOR(MLX_COMPILE_MODE_NO_FUSE),
    ENUMERATOR(MLX_COMPILE_MODE_ENABLED),
    ENUMERATOR(MLX_CPU),
    ENUMERATOR(MLX_GPU),
    ENUMERATOR(MLX_BOOL),
    ENUMERATOR(MLX_UINT8),
    ENUMERATOR(MLX_UINT16),
    ENUMERATOR(MLX_UINT32),
    ENUMERATOR(MLX_UINT64),
    ENUMERATOR(MLX_INT8),
    ENUMERATOR(MLX_INT16),
    ENUMERATOR(MLX_INT32),
    ENUMERATOR(MLX_INT64),
    ENUMERATOR(MLX_FLOAT16),
    ENUMERATOR(MLX_FLOAT32),
    ENUMERATOR(MLX_FLOAT64),
    ENUMERATOR(MLX_BFLOAT16),
    ENUMERATOR(MLX_COMPLEX64),
    ENUMERATOR(MLX_FFT_NORM_BACKWARD),
    ENUMERATOR(MLX_FFT_NORM_ORTHO),
    ENUMERATOR(MLX_FFT_NORM_FORWARD),
};

int mlx_abiprobe_struct_layout(
    const char* name,
    size_t* size,
    size_t* align,
    size_t* offset1,
    size_t* offset2,
    size_t* size1,
    size_t* size2) {
  for (size_t k = 0; k < sizeof(LAYOUTS) / sizeof(LAYOUTS[0]); ++k) {
    if (strcmp(LAYOUTS[k].name, name) == 0) {
      *size = LAYOUTS[k].size;
      *align = LAYOUTS[k].align;
      *offset1 = LAYOUTS[k].offset1;
      *offset2 = LAYOUTS[k].offset2;
      *size1 = LAYOUTS[k].size1;
      *size2 = LAYOUTS[k].size2;
      return 0;
    }
  }
  return 1;
}

int mlx_abiprobe_enum_value(const char* name, int* value) {
  for (size_t k = 0; k < sizeof(ENUMERATORS) / sizeof(ENUMERATORS[0]); ++k) {
    if (strcmp(ENUMERATORS[k].name, name) == 0) {
      *value = ENUMERATORS[k].value;
      return 0;
    }
  }
  return 1;
}
