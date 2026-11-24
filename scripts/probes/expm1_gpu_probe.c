/* expm1_gpu_probe.c -- the accuracy of MLX's float32 expm1 and exp on the CPU and the GPU stream against libm's
   double-precision expm1 and exp, at arguments from -10 to 9.9. Each column is the error relative to
   max(1, |reference|) in float32 epsilons (2^-23). At MLX 0.32.4 the GPU's expm1 grows from about 20 at
   x = 0.5 to about 168 at x = 9.9 while its exp stays below 1 (doc/collaboration/apple_questions.md).

       P=$(brew --prefix)      (or the mlx-c prefix: MLXC_ROOT, .deps/install)
       clang -std=c11 -Wall scripts/probes/expm1_gpu_probe.c -I$P/include -L$P/lib -lmlxc -lm \
             -Wl,-rpath,$P/lib -o /tmp/expm1_gpu_probe && /tmp/expm1_gpu_probe

   It needs a session that sees the GPU (a Terminal, not a headless sandbox). Not part of the build. */
#include <math.h>
#include <stdio.h>
#include "mlx/c/mlx.h"

typedef int (*unary_op)(mlx_array*, const mlx_array, const mlx_stream);

static int run(const char* name, unary_op f, double (*ref)(double), mlx_stream s, const char* dev) {
    float x[] = {-10.f, -5.f, -1.f, -0.25f, -1e-3f, 1e-6f, 1e-3f, 0.25f, 0.5f, 1.f, 2.f, 3.f, 5.f, 8.f, 9.9f};
    int n = (int)(sizeof(x) / sizeof(x[0]));
    int shape[1] = {n};
    mlx_array a = mlx_array_new_data(x, shape, 1, MLX_FLOAT32);
    mlx_array r = mlx_array_new();
    if (f(&r, a, s) != 0 || mlx_array_eval(r) != 0) {
        fprintf(stderr, "%s on the %s failed\n", name, dev);
        return 1;
    }
    const float* y = mlx_array_data_float32(r);
    printf("%-5s %s:", name, dev);
    for (int i = 0; i < n; i++) {
        double e = ref((double)x[i]);
        double rel = fabs((double)y[i] - e) / fmax(1.0, fabs(e));
        printf(" %g:%.2f", x[i], rel / 1.1920928955078125e-07);
    }
    printf("\n");
    mlx_array_free(a);
    mlx_array_free(r);
    return 0;
}

int main(void) {
    int bad = 0;
    mlx_stream cpu = mlx_default_cpu_stream_new();
    mlx_stream gpu = mlx_default_gpu_stream_new();
    printf("x:error/max(1,|ref|) in float32 epsilons\n");
    bad += run("expm1", mlx_expm1, expm1, cpu, "cpu");
    bad += run("expm1", mlx_expm1, expm1, gpu, "gpu");
    bad += run("exp", mlx_exp, exp, cpu, "cpu");
    bad += run("exp", mlx_exp, exp, gpu, "gpu");
    mlx_stream_free(cpu);
    mlx_stream_free(gpu);
    return bad;
}
