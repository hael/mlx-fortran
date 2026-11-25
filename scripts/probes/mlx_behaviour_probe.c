/* mlx_behaviour_probe.c -- MLX behaviour the Fortran wrappers of the parity plan depend on, on the CPU and the
   GPU stream: remainder's sign, round at .5, whether vecdot and inner conjugate, argsort stability,
   searchsorted's sides, which linalg functions refuse the GPU (the norms order by order), a graph that runs an
   inverse on the CPU stream between two GPU operations, and the distributed group without a backend.
   Re-run it on a new MLX release or a new Mac and compare with the parity plan's Phase 0 Progress entry.

       P=$(brew --prefix)      (or the mlx-c prefix: MLXC_ROOT, .deps/install)
       clang -std=c11 -Wall scripts/probes/mlx_behaviour_probe.c -I$P/include -L$P/lib -lmlxc \
             -Wl,-rpath,$P/lib -o /tmp/mlx_behaviour_probe && MLX_ENABLE_TF32=0 /tmp/mlx_behaviour_probe

   MLX_ENABLE_TF32=0 gives full float32 matrix products on the GPU: without it the last product of the
   mixed-stream graph is off by 1e-3.

   It needs a session that sees the GPU (a Terminal, not a headless sandbox). Not part of the build. */
#include <stdio.h>
#include <string.h>
#include <complex.h>
#include "mlx/c/mlx.h"

static char last[512];
static void handler(const char *msg, void *data) { (void)data; snprintf(last, sizeof last, "%s", msg); }

static void show(const char *tag, mlx_array a) {
    if (mlx_array_eval(a)) { printf("%-34s EVAL ERROR: %s\n", tag, last); return; }
    mlx_array f = mlx_array_new();
    mlx_dtype dt = mlx_array_dtype(a);
    if (dt == MLX_COMPLEX64) {
        mlx_real(&f, a, mlx_default_cpu_stream_new());
        mlx_array im = mlx_array_new(); mlx_imag(&im, a, mlx_default_cpu_stream_new());
        mlx_array_eval(f); mlx_array_eval(im);
        printf("%-34s re=", tag);
        for (size_t i = 0; i < mlx_array_size(f); i++) printf(" %g", mlx_array_data_float32(f)[i]);
        printf(" im=");
        for (size_t i = 0; i < mlx_array_size(im); i++) printf(" %g", mlx_array_data_float32(im)[i]);
        printf("\n"); mlx_array_free(im); mlx_array_free(f); return;
    }
    mlx_astype(&f, a, MLX_FLOAT32, mlx_default_cpu_stream_new());
    mlx_array_eval(f);
    printf("%-34s", tag);
    for (size_t i = 0; i < mlx_array_size(f) && i < 12; i++) printf(" %g", mlx_array_data_float32(f)[i]);
    printf("\n");
    mlx_array_free(f);
}

static mlx_array vec32(const float *x, int n) { int s[1] = {n}; return mlx_array_new_data(x, s, 1, MLX_FLOAT32); }

int main(void) {
    mlx_set_error_handler(handler, NULL, NULL);
    mlx_stream cpu = mlx_default_cpu_stream_new(), gpu = mlx_default_gpu_stream_new();
    mlx_string v = mlx_string_new(); mlx_version(&v); printf("MLX %s\n", mlx_string_data(v));

    /* remainder: sign follows the divisor (Fortran modulo) or the dividend (mod)? */
    float an[4] = {-7, 7, -7, 7}, bn[4] = {3, -3, -3, 3};
    mlx_array a = vec32(an, 4), b = vec32(bn, 4), r = mlx_array_new();
    int ai[4] = {-7, 7, -7, 7}, bi[4] = {3, -3, -3, 3}, s4[1] = {4};
    mlx_array ia = mlx_array_new_data(ai, s4, 1, MLX_INT32), ib = mlx_array_new_data(bi, s4, 1, MLX_INT32);
    for (int d = 0; d < 2; d++) {
        mlx_stream s = d ? gpu : cpu; const char *dn = d ? "gpu" : "cpu";
        char t[64];
        snprintf(t, 64, "remainder f32 %s [-7,7,-7,7]%%[3,-3,-3,3]", dn); mlx_remainder(&r, a, b, s); show(t, r);
        snprintf(t, 64, "remainder i32 %s", dn); mlx_remainder(&r, ia, ib, s); show(t, r);
        float rn[6] = {0.5f, 1.5f, 2.5f, -0.5f, -1.5f, 0.25f};
        mlx_array x = vec32(rn, 6);
        snprintf(t, 64, "round %s [.5 1.5 2.5 -.5 -1.5 .25]", dn); mlx_round(&r, x, 0, s); show(t, r);
        mlx_array_free(x);
        /* vecdot: does it conjugate the first operand? [i].[i] = 1 if conjugated, -1 if not */
        float complex ci[1] = {I}; int s1[1] = {1};
        mlx_array c = mlx_array_new_data(ci, s1, 1, MLX_COMPLEX64);
        snprintf(t, 64, "vecdot %s [i].[i] (1=conj,-1=no)", dn); mlx_vecdot(&r, c, c, 0, s); show(t, r);
        snprintf(t, 64, "inner %s [i].[i]", dn); mlx_inner(&r, c, c, s); show(t, r);
        mlx_array_free(c);
        /* sort stability: argsort [1,0,1,0,1,0] -> stable [1 3 5 0 2 4] */
        float sn[6] = {1, 0, 1, 0, 1, 0}; mlx_array y = vec32(sn, 6);
        snprintf(t, 64, "argsort %s [1 0 1 0 1 0]", dn); mlx_argsort_axis(&r, y, 0, s); show(t, r);
        mlx_array_free(y);
        /* larger stability probe: 4096 equal keys in blocks */
        static float big[4096]; for (int i = 0; i < 4096; i++) big[i] = (float)(i % 2);
        mlx_array z = vec32(big, 4096); mlx_array_eval(z);
        if (!mlx_argsort_axis(&r, z, 0, s) && !mlx_array_eval(r)) {
            mlx_array ri = mlx_array_new(); mlx_astype(&ri, r, MLX_INT32, cpu); mlx_array_eval(ri);
            const int *p = mlx_array_data_int32(ri); int stable = 1;
            for (int i = 1; i < 4096; i++) if (big[p[i]] == big[p[i - 1]] && p[i] < p[i - 1]) stable = 0;
            printf("%-34s %s\n", d ? "argsort gpu 4096 ties" : "argsort cpu 4096 ties", stable ? "stable" : "NOT stable");
            mlx_array_free(ri);
        } else printf("argsort 4096 %s ERROR: %s\n", dn, last);
        mlx_array_free(z);
        /* searchsorted sides */
        float ss[4] = {1, 2, 2, 3}, vs[3] = {0, 2, 4};
        mlx_array q = vec32(ss, 4), w = vec32(vs, 3);
        snprintf(t, 64, "searchsorted %s left [1 2 2 3]<-[0 2 4]", dn);
        if (mlx_searchsorted(&r, q, w, "left", s)) printf("%-34s ERROR: %s\n", t, last); else show(t, r);
        snprintf(t, 64, "searchsorted %s right", dn);
        if (mlx_searchsorted(&r, q, w, "right", s)) printf("%-34s ERROR: %s\n", t, last); else show(t, r);
        mlx_array_free(q); mlx_array_free(w);
    }

    /* linalg on the GPU stream: which refuse? */
    float m[9] = {4, 1, 0, 1, 3, 1, 0, 1, 2}; int s33[2] = {3, 3};
    mlx_array A = mlx_array_new_data(m, s33, 2, MLX_FLOAT32), B = vec32(m, 3);
    mlx_array r0 = mlx_array_new(), r1 = mlx_array_new(); mlx_vector_array va = mlx_vector_array_new();
    for (int d = 0; d < 2; d++) {
        mlx_stream s = d ? gpu : cpu; const char *dn = d ? "gpu" : "cpu";
#define TRY(name, call, out) do { last[0] = 0; int st = (call); if (!st) st = mlx_array_eval(out); \
        printf("linalg %-18s %s: %s %s\n", name, dn, st ? "REFUSED" : "ok", st ? last : ""); } while (0)
        TRY("inv", mlx_linalg_inv(&r0, A, s), r0);
        TRY("pinv", mlx_linalg_pinv(&r0, A, s), r0);
        TRY("cholesky", mlx_linalg_cholesky(&r0, A, false, s), r0);
        TRY("cholesky_inv", mlx_linalg_cholesky_inv(&r0, A, false, s), r0);
        TRY("tri_inv", mlx_linalg_tri_inv(&r0, A, false, s), r0);
        TRY("qr", mlx_linalg_qr(&r0, &r1, A, s), r0);
        TRY("eigh", mlx_linalg_eigh(&r0, &r1, A, "L", s), r0);
        TRY("eigvalsh", mlx_linalg_eigvalsh(&r0, A, "L", s), r0);
        TRY("eig", mlx_linalg_eig(&r0, &r1, A, s), r0);
        TRY("eigvals", mlx_linalg_eigvals(&r0, A, s), r0);
        TRY("lu_factor", mlx_linalg_lu_factor(&r0, &r1, A, s), r0);
        TRY("solve", mlx_linalg_solve(&r0, A, B, s), r0);
        TRY("solve_triangular", mlx_linalg_solve_triangular(&r0, A, B, false, s), r0);
        TRY("det", mlx_linalg_det(&r0, A, s), r0);
        TRY("slogdet", mlx_linalg_slogdet(&r0, &r1, A, s), r0);
        TRY("norm_l2", mlx_linalg_norm_l2(&r0, A, NULL, 0, false, s), r0);
        { last[0] = 0; int st = mlx_linalg_svd(&va, A, true, s);
          if (!st) { st = mlx_vector_array_get(&r0, va, 0); if (!st) st = mlx_array_eval(r0); }
          printf("linalg %-18s %s: %s %s\n", "svd", dn, st ? "REFUSED" : "ok", st ? last : ""); }
        { last[0] = 0; int st = mlx_linalg_lu(&va, A, s);
          if (!st) { st = mlx_vector_array_get(&r0, va, 0); if (!st) st = mlx_array_eval(r0); }
          printf("linalg %-18s %s: %s %s\n", "lu", dn, st ? "REFUSED" : "ok", st ? last : ""); }
        /* the norms by order and the cross product: which orders need the CPU (the singular values)? */
        int ax2[2] = {0, 1}, ax1[1] = {1};
        TRY("norm ord=1 vector", mlx_linalg_norm(&r0, A, 1.0, ax1, 1, false, s), r0);
        TRY("norm ord=3 vector", mlx_linalg_norm(&r0, A, 3.0, ax1, 1, false, s), r0);
        TRY("norm ord=1 matrix", mlx_linalg_norm(&r0, A, 1.0, ax2, 2, false, s), r0);
        TRY("norm ord=inf matrix", mlx_linalg_norm(&r0, A, 1.0 / 0.0, ax2, 2, false, s), r0);
        TRY("norm ord=2 matrix", mlx_linalg_norm(&r0, A, 2.0, ax2, 2, false, s), r0);
        TRY("norm ord=-2 matrix", mlx_linalg_norm(&r0, A, -2.0, ax2, 2, false, s), r0);
        TRY("norm_matrix fro", mlx_linalg_norm_matrix(&r0, A, "fro", ax2, 2, false, s), r0);
        TRY("norm_matrix nuc", mlx_linalg_norm_matrix(&r0, A, "nuc", ax2, 2, false, s), r0);
        TRY("norm_l2 axes", mlx_linalg_norm_l2(&r0, A, ax2, 2, false, s), r0);
        TRY("cross", mlx_linalg_cross(&r0, A, A, -1, s), r0);
    }

    /* a graph over both streams, as the wrappers of the CPU-only functions build it under a GPU default: the
       operand made by a GPU operation, the factorisation on the CPU stream, its result used on the GPU */
    { mlx_array t0 = mlx_array_new(), t1 = mlx_array_new(), t2 = mlx_array_new();
      last[0] = 0;
      int st = mlx_add(&t0, A, A, gpu);
      if (!st) st = mlx_linalg_inv(&t1, t0, cpu);
      if (!st) st = mlx_matmul(&t2, t1, t0, gpu);
      if (!st) st = mlx_array_eval(t2);
      if (st) printf("gpu -> cpu inv -> gpu matmul: ERROR %s\n", last); else show("gpu -> cpu inv -> gpu matmul", t2);
      mlx_array_free(t0); mlx_array_free(t1); mlx_array_free(t2); }

    /* distributed: no backend */
    mlx_distributed_group g = mlx_distributed_group_new();
    int avail = mlx_distributed_is_available(NULL);
    printf("distributed_is_available(any) = %d\n", avail);
    last[0] = 0;
    if (mlx_distributed_init(&g, false, NULL)) printf("distributed_init(strict=0): ERROR %s\n", last);
    else { int n = -1, rk = -1; mlx_distributed_group_get_size(&n, g); mlx_distributed_group_get_rank(&rk, g);
           printf("distributed_init(strict=0): size %d rank %d\n", n, rk); }
    return 0;
}
