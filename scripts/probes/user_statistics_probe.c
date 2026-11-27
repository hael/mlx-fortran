/* user_statistics_probe.c -- MLX's mean, variance and standard deviation of integer arrays, called through mlx-c
   without mlx-fortran, on the CPU and the GPU stream: each fixture's exact answer beside MLX's, then the same
   reduction of the input converted to float32 first (the passing control). Every fixture's values are exact in
   float32, so the exact answer is also the float32 answer. A line ends "ok" when the result is within one float32
   epsilon of the answer (relative, or absolute below 1), "WRONG" otherwise, "ERROR" when mlx-c refused it.

       P=$(brew --prefix)      (or the mlx-c prefix: MLXC_ROOT, .deps/install)
       clang -std=c11 -Wall scripts/probes/user_statistics_probe.c -I$P/include -L$P/lib -lmlxc \
             -Wl,-rpath,$P/lib -o /tmp/user_statistics_probe && MLX_ENABLE_TF32=0 /tmp/user_statistics_probe

   It needs a session that sees the GPU (a Terminal, not a headless sandbox); without one it runs the CPU only.
   Not part of the build. The exit status is 0 whatever MLX returns: the printed lines are the finding. */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "mlx/c/mlx.h"

static char last[512];
static void handler(const char *msg, void *data) { (void)data; snprintf(last, sizeof last, "%s", msg); }

/* the value of a rank-0 (or one-element) result, as a double; NAN after a failure */
static double scalar(mlx_array a, mlx_stream cpu) {
    if (mlx_array_eval(a)) return NAN;
    mlx_array f = mlx_array_new();
    double v = NAN;
    if (!mlx_astype(&f, a, MLX_FLOAT64, cpu) && !mlx_array_eval(f)) v = mlx_array_data_float64(f)[0];
    mlx_array_free(f);
    return v;
}

static int close32(double got, double want) {
    double scale = fabs(want) > 1.0 ? fabs(want) : 1.0;
    return isfinite(got) && fabs(got - want) <= 1.1920929e-7 * scale;
}

/* one line: op of the fixture on the stream, the dtype MLX returned, the value and the verdict */
static void report(const char *fixture, const char *dev, const char *op, int rc, mlx_array r, double want,
                   mlx_stream cpu) {
    if (rc) { printf("%-28s %-3s %-12s ERROR: %s\n", fixture, dev, op, last); return; }
    double got = scalar(r, cpu);
    printf("%-28s %-3s %-12s dtype %2d  got %-16.9g want %-14.9g %s\n", fixture, dev, op,
           (int)mlx_array_dtype(r), got, want, close32(got, want) ? "ok" : "WRONG");
}

/* mean, var and std (ddof 0 and, for n > 2, ddof 1) of a, then of a converted to float32 */
static void run(const char *fixture, mlx_array a, double mean, double var, mlx_stream s, const char *dev,
                mlx_stream cpu) {
    mlx_array r = mlx_array_new(), f = mlx_array_new();
    report(fixture, dev, "mean", mlx_mean(&r, a, false, s), r, mean, cpu);
    report(fixture, dev, "var", mlx_var(&r, a, false, 0, s), r, var, cpu);
    report(fixture, dev, "std", mlx_std(&r, a, false, 0, s), r, sqrt(var), cpu);
    report(fixture, dev, "mean_axis0", mlx_mean_axis(&r, a, 0, false, s), r, mean, cpu);
    if (mlx_astype(&f, a, MLX_FLOAT32, s)) { printf("%-28s %-3s astype ERROR: %s\n", fixture, dev, last); }
    else {
        report(fixture, dev, "f32 mean", mlx_mean(&r, f, false, s), r, mean, cpu);
        report(fixture, dev, "f32 var", mlx_var(&r, f, false, 0, s), r, var, cpu);
        report(fixture, dev, "f32 std", mlx_std(&r, f, false, 0, s), r, sqrt(var), cpu);
    }
    mlx_array_free(f);
    mlx_array_free(r);
}

/* a constant array of n elements of the given dtype, made from a double value */
static mlx_array constant(int n, double v, mlx_dtype dt, mlx_stream cpu) {
    int shape[1] = {n};
    mlx_array val = mlx_array_new_float64(v), r = mlx_array_new();
    if (dt == MLX_INT64 || dt == MLX_UINT64) {  /* made from the integer itself, never through a double */
        mlx_array_free(val);
        val = dt == MLX_INT64 ? mlx_array_new_data(&(int64_t){(int64_t)v}, NULL, 0, MLX_INT64)
                              : mlx_array_new_data(&(uint64_t){(uint64_t)v}, NULL, 0, MLX_UINT64);
    }
    mlx_full(&r, shape, 1, val, dt, cpu);
    mlx_array_eval(r);
    mlx_array_free(val);
    return r;
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

    /* the dtypes and values of the constant fixtures: each value is exact in float32 and its dtype */
    struct { const char *name; mlx_dtype dt; double v; int n; } c[] = {
        {"int32 1024x1024 of 4096", MLX_INT32, 4096.0, 1024 * 1024},
        {"int32 2 of 2000000000", MLX_INT32, 2000000000.0, 2},
        {"uint32 2 of 4000000000", MLX_UINT32, 4000000000.0, 2},
        {"int64 2 of 2^62", MLX_INT64, 4611686018427387904.0, 2},
        {"uint64 2 of 2^63", MLX_UINT64, 9223372036854775808.0, 2},
        {"int16 65536 of 30000", MLX_INT16, 30000.0, 65536},
        {"uint16 65536 of 60000", MLX_UINT16, 60000.0, 65536},
        {"int8 4096 of 100", MLX_INT8, 100.0, 4096},
        {"uint8 4096 of 200", MLX_UINT8, 200.0, 4096},
        {"bool 4096 of true", MLX_BOOL, 1.0, 4096},
    };
    for (int d = 0; d < (ngpu > 0 ? 2 : 1); d++) {
        mlx_stream s = d ? gpu : cpu;
        const char *dev = d ? "gpu" : "cpu";
        for (size_t k = 0; k < sizeof c / sizeof c[0]; k++) {
            mlx_array a = constant(c[k].n, c[k].v, c[k].dt, cpu);
            run(c[k].name, a, c[k].v, 0.0, s, dev, cpu);
            mlx_array_free(a);
        }
        /* signed cancellation: [2e9, -2e9, 2e9, -2e9] has mean 0 and variance 4e18, which float32 rounds to
           3.99999994e18: the reference is the exact value, held to a float32 epsilon */
        int32_t sc[4] = {2000000000, -2000000000, 2000000000, -2000000000};
        int s4[1] = {4};
        mlx_array a = mlx_array_new_data(sc, s4, 1, MLX_INT32);
        run("int32 [2e9,-2e9,2e9,-2e9]", a, 0.0, 4.0e18, s, dev, cpu);
        mlx_array_free(a);
    }
    mlx_stream_free(gpu);
    mlx_stream_free(cpu);
    return 0;
}
