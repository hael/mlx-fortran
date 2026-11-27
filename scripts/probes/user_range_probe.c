/* user_range_probe.c -- MLX's Euclidean norm and floating mean at the ends of the floating range, and its maximum
   and minimum of an empty extent, called through mlx-c without mlx-fortran, on the CPU and the GPU stream (float64
   on the CPU only). Each norm and mean fixture has a closed-form answer: two equal values x give the norm
   sqrt(2)*|x| and the mean x. Beside MLX's reduction runs a control: the same norm scaled by the largest magnitude,
   s*norm(a/s), and the mean as the sum of halves, which keep every intermediate representable. A line ends "ok"
   when the result is finite and within 8 epsilons of the result kind (relative), "WRONG" otherwise, "ERROR" when
   mlx-c refused it; the empty lines print what MLX returned or its message.

       P=$(brew --prefix)      (or the mlx-c prefix: MLXC_ROOT, .deps/install)
       clang -std=c11 -Wall scripts/probes/user_range_probe.c -I$P/include -L$P/lib -lmlxc \
             -Wl,-rpath,$P/lib -o /tmp/user_range_probe && MLX_ENABLE_TF32=0 /tmp/user_range_probe

   It needs a session that sees the GPU (a Terminal, not a headless sandbox); without one it runs the CPU only.
   Not part of the build. The exit status is 0 whatever MLX returns: the printed lines are the finding. */
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "mlx/c/mlx.h"

static char last[512];
static void handler(const char *msg, void *data) { (void)data; snprintf(last, sizeof last, "%s", msg); }

static double scalar(mlx_array a, mlx_stream cpu) {
    if (mlx_array_eval(a)) return NAN;
    mlx_array f = mlx_array_new();
    double v = NAN;
    if (!mlx_astype(&f, a, MLX_FLOAT64, cpu) && !mlx_array_eval(f)) v = mlx_array_data_float64(f)[0];
    mlx_array_free(f);
    return v;
}

static void report(const char *fixture, const char *dev, const char *op, int rc, mlx_array r, double want,
                   double eps, mlx_stream cpu) {
    if (rc) { printf("%-24s %-3s %-14s ERROR: %s\n", fixture, dev, op, last); return; }
    double got = scalar(r, cpu);
    int ok = isfinite(got) && fabs(got - want) <= 8.0 * eps * fabs(want);
    printf("%-24s %-3s %-14s got %-16.9g want %-16.9g %s\n", fixture, dev, op, got, want, ok ? "ok" : "WRONG");
}

/* norm and mean of the two-element array [x, x] of dtype dt, and the scaled controls */
static void pair(double x, mlx_dtype dt, mlx_stream s, const char *dev, mlx_stream cpu) {
    char fixture[64];
    double eps = dt == MLX_FLOAT64 ? 2.220446049250313e-16 : 1.1920929e-7;
    snprintf(fixture, sizeof fixture, "%s [%g,%g]", dt == MLX_FLOAT64 ? "f64" : "f32", x, x);
    int shape[1] = {2};
    mlx_array one = mlx_array_new_float64(x), a = mlx_array_new(), r = mlx_array_new(), t = mlx_array_new(),
              m = mlx_array_new(), h = mlx_array_new();
    mlx_full(&a, shape, 1, one, dt, cpu);  /* the float64 fill value exists on the CPU only */
    mlx_array_eval(a);
    if (dt == MLX_FLOAT32) x = (double)(float)x;  /* the stored value */
    report(fixture, dev, "norm_l2", mlx_linalg_norm_l2(&r, a, NULL, 0, false, s), r, sqrt(2.0) * fabs(x), eps, cpu);
    report(fixture, dev, "norm ord 2", mlx_linalg_norm(&r, a, 2.0, NULL, 0, false, s), r, sqrt(2.0) * fabs(x), eps,
           cpu);
    /* control: s = max|a|, s * norm(a / s) */
    int rc = mlx_abs(&t, a, s) || mlx_max(&m, t, false, s) || mlx_divide(&t, a, m, s)
             || mlx_linalg_norm_l2(&h, t, NULL, 0, false, s) || mlx_multiply(&r, h, m, s);
    report(fixture, dev, "scaled norm", rc, r, sqrt(2.0) * fabs(x), eps, cpu);
    report(fixture, dev, "mean", mlx_mean(&r, a, false, s), r, x, eps, cpu);
    /* control: the sum of a/2 */
    mlx_array half = mlx_array_new_float(0.5f);  /* float32: a float64 scalar would make the GPU graph float64 */
    rc = mlx_multiply(&t, a, half, s) || mlx_sum(&r, t, false, s);
    report(fixture, dev, "sum of halves", rc, r, x, eps, cpu);
    mlx_array_free(half);
    mlx_array_free(h);
    mlx_array_free(m);
    mlx_array_free(t);
    mlx_array_free(r);
    mlx_array_free(a);
    mlx_array_free(one);
}

/* max and min along MLX axis 1 (Fortran dimension 1) of an MLX [3, 0] array, the Fortran shape (0, 3) */
static void empty(mlx_dtype dt, const char *name, mlx_stream s, const char *dev) {
    int shape[2] = {3, 0};
    mlx_array a = mlx_array_new(), r = mlx_array_new();
    mlx_zeros(&a, shape, 2, dt, s);
    for (int k = 0; k < 2; k++) {
        const char *op = k ? "min axis" : "max axis";
        int rc = k ? mlx_min_axis(&r, a, 1, false, s) : mlx_max_axis(&r, a, 1, false, s);
        if (!rc) rc = mlx_array_eval(r);
        if (rc) printf("empty %-18s %-3s %-14s ERROR: %s\n", name, dev, op, last);
        else printf("empty %-18s %-3s %-14s size %zu (no error)\n", name, dev, op, mlx_array_size(r));
    }
    mlx_array_free(r);
    mlx_array_free(a);
}

int main(void) {
    mlx_set_error_handler(handler, NULL, NULL);
    mlx_stream cpu = mlx_default_cpu_stream_new(), gpu = mlx_default_gpu_stream_new();
    mlx_string ver = mlx_string_new();
    mlx_version(&ver);
    int ngpu = 0;
    mlx_device_count(&ngpu, MLX_GPU);
    printf("MLX %s; GPU devices %d\n", mlx_string_data(ver), ngpu);
    mlx_string_free(ver);
    for (int d = 0; d < (ngpu > 0 ? 2 : 1); d++) {
        mlx_stream s = d ? gpu : cpu;
        const char *dev = d ? "gpu" : "cpu";
        double f32[] = {3.0, 1e20, 1e-30, 2e38};
        for (size_t k = 0; k < sizeof f32 / sizeof f32[0]; k++) pair(f32[k], MLX_FLOAT32, s, dev, cpu);
        if (!d) {
            double f64[] = {3.0, 1e200, 1e-200, 1e308};
            for (size_t k = 0; k < sizeof f64 / sizeof f64[0]; k++) pair(f64[k], MLX_FLOAT64, s, dev, cpu);
        }
        empty(MLX_FLOAT32, "(0,3) float32", s, dev);
        empty(MLX_INT32, "(0,3) int32", s, dev);
    }
    mlx_stream_free(gpu);
    mlx_stream_free(cpu);
    return 0;
}
