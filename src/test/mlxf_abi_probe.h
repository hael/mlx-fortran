/* src/test/mlxf_abi_probe.h -- the ABI probe of the generated bind(c) layer: echo functions in mlx-c's own types.
 *
 * scripts/gen_mlxc_bindings.py --probe writes the Fortran interfaces of these prototypes with the mapping table
 * that writes the library's (build/gen_test/mlxf_c_abi_probe.f90); src/test/mlxf_abi_probe.c implements them,
 * compiled by Apple's clang, the compiler of mlx-c; src/test/mlxf_abi_tester.f90 calls them (unit_core, suite abi).
 * Each function returns what it received, so a Fortran interface whose type or passing mode differs from C's reads
 * back something else. Every class of argument and result of the generated layer appears at least once; int, bool,
 * float, double and the three optional pairs both in a register and on the stack (after eight integer and eight
 * floating-point arguments, where Apple's arm64 rule packs them by their own size). The layouts: every struct's
 * size, alignment and field offsets and every enumerator's value, by name, as C sees them. Test-only: never part of
 * the library. Each function returns 0, or a positive code when a filler argument arrived wrong.
 */
#ifndef MLXF_ABI_PROBE_H
#define MLXF_ABI_PROBE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include "mlx/c/mlx.h"

#ifdef __cplusplus
extern "C" {
#endif

/* scalars by value in a register, read back through a pointer of the same type */
int mlx_abiprobe_int(int* res, int v);
int mlx_abiprobe_bool(bool* res, bool v);
int mlx_abiprobe_float(float* res, float v);
int mlx_abiprobe_double(double* res, double v);
int mlx_abiprobe_size(size_t* res, size_t v);
int mlx_abiprobe_uint64(uint64_t* res, uint64_t v);
int mlx_abiprobe_uintptr(void** res, uintptr_t v);
int mlx_abiprobe_dtype(mlx_dtype* res, mlx_dtype v);
/* the optional pairs by value in a register */
int mlx_abiprobe_optional_int(mlx_optional_int* res, mlx_optional_int v);
int mlx_abiprobe_optional_float(mlx_optional_float* res, mlx_optional_float v);
int mlx_abiprobe_optional_dtype(mlx_optional_dtype* res, mlx_optional_dtype v);
/* the same on the stack: eight integer-class and eight floating-point fillers (1 to 4, 1.5 to 8.5) first */
int mlx_abiprobe_stack(
    int* ri,
    bool* rb,
    float* rf,
    double* rd,
    int f1,
    int f2,
    int f3,
    int f4,
    double g1,
    double g2,
    double g3,
    double g4,
    double g5,
    double g6,
    double g7,
    double g8,
    bool b,
    int i,
    float f,
    double d);
int mlx_abiprobe_stack_optional(
    mlx_optional_int* roi,
    mlx_optional_float* rof,
    mlx_optional_dtype* rod,
    int f1,
    int f2,
    int f3,
    int f4,
    int f5,
    mlx_optional_int oi,
    mlx_optional_float of,
    mlx_optional_dtype od);
/* pointers to the fixed-size integers (signed and unsigned), float, double and complex64: each value doubled */
int mlx_abiprobe_refs(
    int8_t* a,
    int16_t* b,
    int32_t* c,
    int64_t* d,
    float* e,
    double* f,
    mlx_complex64_t* g);
int mlx_abiprobe_urefs(uint8_t* a, uint16_t* b, uint32_t* c, uint64_t* d);
/* arrays the callee reads: sum of (k + 1) * a[k] */
int mlx_abiprobe_int_array(int* res, const int* a, size_t n);
int mlx_abiprobe_int64_arrays(int64_t* res, const int64_t* a, const uint64_t* b, size_t n);
/* handles: by value, by reference, an array of them, as a result; a two-pointer iterator by value and as result */
mlx_array mlx_abiprobe_handle(const mlx_array a);
int mlx_abiprobe_handle_ref(mlx_array* res, const mlx_array a);
int mlx_abiprobe_handles(mlx_array* res, const mlx_array* arr, size_t num);
mlx_map_string_to_array_iterator mlx_abiprobe_iterator(void* ctx, void* map_ctx);
int mlx_abiprobe_iterator_echo(void** ctx, void** map_ctx, mlx_map_string_to_array_iterator it);
/* pointers, strings and a function pointer */
void* mlx_abiprobe_pointer(void* p);
int mlx_abiprobe_pointer_ref(void** res, void* p);
int mlx_abiprobe_file(void** res, FILE* f);
int mlx_abiprobe_strlen(size_t* res, const char* s);
int mlx_abiprobe_string(const char** res, int which);
int mlx_abiprobe_chars(char** res, void* s);
int mlx_abiprobe_funptr(int* res, int (*fun)(int), int v);
/* the other results */
int mlx_abiprobe_int_result(int v);
size_t mlx_abiprobe_size_result(size_t v);
bool mlx_abiprobe_bool_result(bool v);
void mlx_abiprobe_void(int* res, int v);
/* the layouts as C sees them, by C name (the offsets and sizes of the first two fields): 1 when the name is unknown */
int mlx_abiprobe_struct_layout(
    const char* name,
    size_t* size,
    size_t* align,
    size_t* offset1,
    size_t* offset2,
    size_t* size1,
    size_t* size2);
int mlx_abiprobe_enum_value(const char* name, int* value);

#ifdef __cplusplus
}
#endif

#endif
