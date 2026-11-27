!@descr: the kernel-forms benchmark's Metal sources and their specs: the probe's kernels and the alternative forms
! The current forms are not here: the benchmark builds them from the toys' own spec functions, and a form derived
! from a current one (the tail without its compensation) is derived from that spec's source at run time. Every
! source sees MLX's layout, row-major and 0-based; sizes come from the inputs' shapes or from template integers.
module mlxf_bench_kernel_forms_src
use mlxf,                       only: mlx_custom_kernel_spec, MLX_DTYPES
use mlxf_test_defs,             only: polarft_tile_spec
use mlxf_toy_polarft_workspace, only: tail_spec
implicit none
private

public :: group_sum_spec, simd_probe_spec, tgmem_probe_spec, tail_simd_spec, tail_plain_spec, reduce_spec
public :: sizes_in_input, select_spec, insert_pull_spec

character(len=1), parameter :: NL = achar(10)
! the forms of the reduction, by index: serial, serial compensated, the threadgroup tree
integer, parameter :: REDUCE_SERIAL = 0
integer, parameter :: REDUCE_KAHAN  = 1
integer, parameter :: REDUCE_TREE   = 2
! ---- the probe ----
! the group sum: each thread stores its value in the group's array, then a tree halves the active threads with a
! barrier after every level; thread 0 writes the group's sum. The array holds the largest group, 1,024 floats
character(len=*), parameter :: GROUP_LOAD = &
    &'threadgroup float sh[1024];'//NL// &
    &'const uint t = thread_position_in_threadgroup.x;'//NL// &
    &'const uint n = threads_per_threadgroup.x;'//NL// &
    &'const uint g = threadgroup_position_in_grid.x;'//NL// &
    &'sh[t] = x[g * n + t];'//NL
character(len=*), parameter :: GROUP_BARRIER = 'threadgroup_barrier(mem_flags::mem_threadgroup);'//NL
character(len=*), parameter :: GROUP_LEVEL = &
    &'for (uint s = n / 2; s > 0; s >>= 1) {'//NL// &
    &'  if (t < s) sh[t] += sh[t + s];'//NL
character(len=*), parameter :: GROUP_TAIL = '}'//NL//'if (t == 0) out[g] = sh[0];'
! the SIMD-group functions: per thread its lane, its SIMD group, the group's width, then the sum, the minimum, the
! inclusive prefix sum and the value of the mirrored lane 31 - lane, written as res[7 i + k]
character(len=*), parameter :: SIMD_SOURCE = &
    &'const uint i = thread_position_in_grid.x;'//NL// &
    &'const uint lane = thread_index_in_simdgroup;'//NL// &
    &'const float v = x[i];'//NL// &
    &'res[7 * i] = float(lane);'//NL// &
    &'res[7 * i + 1] = float(simdgroup_index_in_threadgroup);'//NL// &
    &'res[7 * i + 2] = float(threads_per_simdgroup);'//NL// &
    &'res[7 * i + 3] = simd_sum(v);'//NL// &
    &'res[7 * i + 4] = simd_min(v);'//NL// &
    &'res[7 * i + 5] = simd_prefix_inclusive_sum(v);'//NL// &
    &'res[7 * i + 6] = simd_shuffle(v, ushort(31 - lane));'
! a threadgroup array of NF floats (a template): filled with its indices by the group, then read mirrored
character(len=*), parameter :: TGMEM_SOURCE = &
    &'threadgroup float sh[NF];'//NL// &
    &'const uint t = thread_position_in_threadgroup.x;'//NL// &
    &'for (uint j = t; j < uint(NF); j += threads_per_threadgroup.x) sh[j] = float(j);'//NL// &
    &'threadgroup_barrier(mem_flags::mem_threadgroup);'//NL// &
    &'out[t] = sh[uint(NF) - 1 - t] + x[t];'
! ---- the tail: one SIMD group of 32 lanes per pair ----
! the pair of the group and its constants, as the current tail reads them (rows (nrots, rt, bt) are MLX's
! [bt, rt, nrots]); nr is the rotations every sweep visits
character(len=*), parameter :: T1_HEAD = &
    &'const uint lane = thread_index_in_simdgroup;'//NL// &
    &'const uint e = thread_position_in_grid.x / 32;'//NL// &
    &'const uint nrots = raw_shape[2];'//NL// &
    &'const uint rt = raw_shape[1];'//NL// &
    &'if (e >= raw_shape[0] * rt) return;'//NL// &
    &'const uint nr = nrots;'//NL// &
    &'const uint base = e * nrots;'//NL// &
    &'const float w = iw[e / rt];'//NL// &
    &'const float tmp = temps[e / rt];'//NL// &
    &'const float uu = u[e];'//NL// &
    &'const float dmax = par[0];'//NL// &
    &'const float dbad = par[1];'//NL// &
    &'const float dvalid = par[2];'//NL// &
    &'const float cut = par[3];'//NL// &
    &'const float flr = par[4];'//NL
! each lane's first minimum over its rotations lane, lane + 32, ...; the group's minimum, then the least rotation
! of the lanes that hold it (the first minimum of the row; none valid: rotation 0)
character(len=*), parameter :: T1_MIN = &
    &'float lmin = dbad;'//NL// &
    &'uint limin = 0xFFFFFFFFu;'//NL// &
    &'for (uint i = lane; i < nr; i += 32) {'//NL// &
    &'  float d = fma(raw[base + i], w, 1.0f);'//NL// &
    &'  if (!(d <= dmax)) d = dbad;'//NL// &
    &'  if (d < dvalid && d < lmin) { lmin = d; limin = i; }'//NL// &
    &'}'//NL// &
    &'const float dmin = simd_min(lmin);'//NL// &
    &'uint imin = simd_min((limin != 0xFFFFFFFFu && lmin == dmin) ? limin : 0xFFFFFFFFu);'//NL// &
    &'if (imin == 0xFFFFFFFFu) imin = 0;'//NL
! the weight of rotation i into wgt, ok when it counts (valid and below the cutoff), as the current tail's
character(len=*), parameter :: T1_WEIGHT = &
    &'    float d = fma(raw[base + i], w, 1.0f);'//NL// &
    &'    if (!(d <= dmax)) d = dbad;'//NL// &
    &'    if (d < dvalid) {'//NL// &
    &'      const float a = (d - dmin) * tmp;'//NL// &
    &'      if (a < cut) { wgt = metal::precise::exp(-a); ok = true; }'//NL// &
    &'    }'//NL
! W from the lanes' partial sums; the draw over blocks of 32 rotations in order: the block's inclusive prefix
! sums on the carry, the least lane whose counted weight reaches the target; lane 0 writes the entry
character(len=*), parameter :: T1_DRAW = &
    &'float ls = 0.0f;'//NL// &
    &'for (uint i = lane; i < nr; i += 32) {'//NL// &
    &'  float wgt = 0.0f;'//NL// &
    &'  bool ok = false;'//NL// &
    &'  {'//NL//T1_WEIGHT//'  }'//NL// &
    &'  ls += wgt;'//NL// &
    &'}'//NL// &
    &'const float tgt = metal::max(uu * simd_sum(ls), flr);'//NL// &
    &'uint pick = imin;'//NL// &
    &'float carry = 0.0f;'//NL// &
    &'for (uint k0 = 0; k0 < nr; k0 += 32) {'//NL// &
    &'  const uint i = k0 + lane;'//NL// &
    &'  float wgt = 0.0f;'//NL// &
    &'  bool ok = false;'//NL// &
    &'  if (i < nr) {'//NL//T1_WEIGHT//'  }'//NL// &
    &'  const float pre = carry + simd_prefix_inclusive_sum(wgt);'//NL// &
    &'  const uint hit = simd_min((ok && pre >= tgt) ? lane : 32u);'//NL// &
    &'  if (hit < 32u) { pick = k0 + hit; break; }'//NL// &
    &'  carry = simd_broadcast(pre, ushort(31));'//NL// &
    &'}'//NL// &
    &'if (lane == 0) {'//NL// &
    &'  float dp = fma(raw[base + pick], w, 1.0f);'//NL// &
    &'  if (!(dp <= dmax)) dp = dbad;'//NL// &
    &'  dists[e] = dp;'//NL// &
    &'  irots[e] = int(pick) + 1;'//NL// &
    &'}'
! the current tail's compensated step, and the plain sum that replaces it
character(len=*), parameter :: KAHAN_STEP = &
    &'  float y = metal::precise::exp(-a) - c;'//NL// &
    &'  float t = s + y;'//NL// &
    &'  c = (t - s) - y;'//NL// &
    &'  s = t;'//NL
character(len=*), parameter :: PLAIN_STEP = '  s += metal::precise::exp(-a);'//NL
! ---- the reduction: NS sums per evaluation e of the terms x[e, j] y[j, k] over j ----
character(len=*), parameter :: R_HEAD = &
    &'const uint ne = x_shape[0];'//NL// &
    &'const uint nt = x_shape[1];'//NL
! one thread per evaluation, the terms in index order, a register accumulator per sum
character(len=*), parameter :: R0_BODY = &
    &'const uint e = thread_position_in_grid.x;'//NL// &
    &'if (e >= ne) return;'//NL// &
    &'float acc[NS];'//NL// &
    &'for (uint k = 0; k < uint(NS); ++k) acc[k] = 0.0f;'//NL// &
    &'for (uint j = 0; j < nt; ++j) {'//NL// &
    &'  const float xv = x[e * nt + j];'//NL// &
    &'  for (uint k = 0; k < uint(NS); ++k) acc[k] += xv * y[j * uint(NS) + k];'//NL// &
    &'}'//NL// &
    &'for (uint k = 0; k < uint(NS); ++k) out[e * uint(NS) + k] = acc[k];'
! the same with a compensated sum per accumulator
character(len=*), parameter :: R1_BODY = &
    &'const uint e = thread_position_in_grid.x;'//NL// &
    &'if (e >= ne) return;'//NL// &
    &'float acc[NS];'//NL// &
    &'float cmp[NS];'//NL// &
    &'for (uint k = 0; k < uint(NS); ++k) { acc[k] = 0.0f; cmp[k] = 0.0f; }'//NL// &
    &'for (uint j = 0; j < nt; ++j) {'//NL// &
    &'  const float xv = x[e * nt + j];'//NL// &
    &'  for (uint k = 0; k < uint(NS); ++k) {'//NL// &
    &'    const float v = xv * y[j * uint(NS) + k] - cmp[k];'//NL// &
    &'    const float t = acc[k] + v;'//NL// &
    &'    cmp[k] = (t - acc[k]) - v;'//NL// &
    &'    acc[k] = t;'//NL// &
    &'  }'//NL// &
    &'}'//NL// &
    &'for (uint k = 0; k < uint(NS); ++k) out[e * uint(NS) + k] = acc[k];'
! one threadgroup of TG threads per evaluation: each thread's partials over the terms t, t + TG, ...; simd_sum
! per SIMD group into the group's array; after the barrier thread 0 adds the NSG SIMD sums in index order
character(len=*), parameter :: R2_PARTIALS = &
    &'threadgroup float sh[NSG * NS];'//NL// &
    &'const uint e = threadgroup_position_in_grid.x;'//NL// &
    &'const uint t = thread_position_in_threadgroup.x;'//NL// &
    &'const uint lane = thread_index_in_simdgroup;'//NL// &
    &'const uint sg = simdgroup_index_in_threadgroup;'//NL// &
    &'float acc[NS];'//NL// &
    &'for (uint k = 0; k < uint(NS); ++k) acc[k] = 0.0f;'//NL// &
    &'for (uint j = t; j < nt; j += uint(TG)) {'//NL// &
    &'  const float xv = x[e * nt + j];'//NL// &
    &'  for (uint k = 0; k < uint(NS); ++k) acc[k] += xv * y[j * uint(NS) + k];'//NL// &
    &'}'//NL// &
    &'for (uint k = 0; k < uint(NS); ++k) {'//NL// &
    &'  const float v = simd_sum(acc[k]);'//NL// &
    &'  if (lane == 0) sh[sg * uint(NS) + k] = v;'//NL// &
    &'}'//NL
character(len=*), parameter :: R2_TOTAL = &
    &'if (t == 0) {'//NL// &
    &'  for (uint k = 0; k < uint(NS); ++k) {'//NL// &
    &'    float s = 0.0f;'//NL// &
    &'    for (uint g = 0; g < uint(NSG); ++g) s += sh[g * uint(NS) + k];'//NL// &
    &'    out[e * uint(NS) + k] = s;'//NL// &
    &'  }'//NL// &
    &'}'
! ---- the selection: the K best (largest) of each particle's column of the table, MLX's [npart, nref] ----
! the insertion of value v at reference r into the descending list (bv, bi) of K, by strict comparison: an equal
! value never displaces an earlier one, so ties keep the lower index
character(len=*), parameter :: SEL_INSERT = &
    &'  if (v > bv[K - 1]) {'//NL// &
    &'    int j = K - 1;'//NL// &
    &'    while (j > 0 && v > bv[j - 1]) { bv[j] = bv[j - 1]; bi[j] = bi[j - 1]; --j; }'//NL// &
    &'    bv[j] = v;'//NL// &
    &'    bi[j] = int(r);'//NL// &
    &'  }'//NL
character(len=*), parameter :: SEL_INIT = &
    &'const uint nref = t_shape[1];'//NL// &
    &'float bv[K];'//NL// &
    &'int bi[K];'//NL// &
    &'for (int j = 0; j < K; ++j) { bv[j] = -INFINITY; bi[j] = 0; }'//NL
! one thread per particle: its column in index order, then its list written as (K, npart), 1-based indices
character(len=*), parameter :: E2_SOURCE = &
    &'const uint p = thread_position_in_grid.x;'//NL// &
    &'if (p >= t_shape[0]) return;'//NL//SEL_INIT// &
    &'for (uint r = 0; r < nref; ++r) {'//NL// &
    &'  const float v = t[p * nref + r];'//NL//SEL_INSERT// &
    &'}'//NL// &
    &'for (int j = 0; j < K; ++j) { val[p * K + j] = bv[j]; idx[p * K + j] = bi[j] + 1; }'
! one SIMD group per particle: each lane's list over the references lane, lane + 32, ...; then K rounds of the
! merge: the largest head, of the lanes holding it the lowest index, whose lane advances; lane 0 writes
character(len=*), parameter :: E3_SOURCE = &
    &'const uint lane = thread_index_in_simdgroup;'//NL// &
    &'const uint p = thread_position_in_grid.x / 32;'//NL// &
    &'if (p >= t_shape[0]) return;'//NL//SEL_INIT// &
    &'for (uint r = lane; r < nref; r += 32) {'//NL// &
    &'  const float v = t[p * nref + r];'//NL//SEL_INSERT// &
    &'}'//NL// &
    &'int h = 0;'//NL// &
    &'for (int j = 0; j < K; ++j) {'//NL// &
    &'  const float hv = (h < K) ? bv[h] : -INFINITY;'//NL// &
    &'  const int hi = (h < K) ? bi[h] : 0x7FFFFFFF;'//NL// &
    &'  const float m = simd_max(hv);'//NL// &
    &'  const int wi = simd_min((hv == m) ? hi : 0x7FFFFFFF);'//NL// &
    &'  if (hv == m && hi == wi) ++h;'//NL// &
    &'  if (lane == 0) { val[p * K + j] = m; idx[p * K + j] = wi + 1; }'//NL// &
    &'}'

! ---- the insertion as a pull: one thread per voxel, 8 x 8 x 8 voxels a threadgroup ----
! the sizes from par (the probe's five templates, then the Nyquist index and the planes), the voxel, the tile's
! centre (logical coordinates, the same for the whole group) and the window's constants
character(len=*), parameter :: PULL_HEAD = &
    &'const int NPIX = par[0];'//NL// &
    &'const int HL = par[1];'//NL// &
    &'const int HK = par[2];'//NL// &
    &'const int NH = par[3];'//NL// &
    &'const int NK = par[4];'//NL// &
    &'const int NYQ = par[5];'//NL// &
    &'const int NB = par[6];'//NL// &
    &'const uint3 gid = thread_position_in_grid;'//NL// &
    &'const bool act = gid.x < uint(NH) && gid.y < uint(NK) && gid.z < uint(NK);'//NL// &
    &'const int gx = int(gid.x) - HL;'//NL// &
    &'const int gy = int(gid.y) - HK;'//NL// &
    &'const int gz = int(gid.z) - HK;'//NL// &
    &'const uint3 grp = threadgroup_position_in_grid;'//NL// &
    &'const float cx = float(int(grp.x) * 8 - HL) + 3.5f;'//NL// &
    &'const float cy = float(int(grp.y) * 8 - HK) + 3.5f;'//NL// &
    &'const float cz = float(int(grp.z) * 8 - HK) + 3.5f;'//NL// &
    &'const float twoow = coef[15];'//NL// &
    &'const float oneow = coef[16];'//NL// &
    &'float ar = 0.0f;'//NL// &
    &'float ai = 0.0f;'//NL// &
    &'float ad = 0.0f;'//NL
! each plane in batch order: one test of the plane's distance from the tile's centre that the whole group takes
! alike (a tile's half-diagonal 3.5 sqrt 3 plus a voxel's reach 1.5 sqrt 3, rounded up to 9)
character(len=*), parameter :: PULL_PLANE = &
    &'for (int p = 0; p < NB; ++p) {'//NL// &
    &'  const uint o = 9 * uint(p);'//NL// &
    &'  if (metal::fabs(cx * rot[o + 2] + cy * rot[o + 5] + cz * rot[o + 8]) > 9.0f) continue;'//NL// &
    &'  const float om = omega[p];'//NL
! the staged form: the patch of pixels that covers the tile's projection (with a margin of 3), loaded by the
! group from global memory, zeros where no pixel holds data
character(len=*), parameter :: PULL_STAGE = &
    &'  const float l1h = metal::fabs(rot[o]) + metal::fabs(rot[o + 3]) + metal::fabs(rot[o + 6]);'//NL// &
    &'  const float l1k = metal::fabs(rot[o + 1]) + metal::fabs(rot[o + 4]) + metal::fabs(rot[o + 7]);'//NL// &
    &'  const int hlo = int(metal::floor(cx * rot[o] + cy * rot[o + 3] + cz * rot[o + 6] - 3.5f * l1h)) - 3;'//NL// &
    &'  const int klo = int(metal::floor(cx * rot[o + 1] + cy * rot[o + 4] + cz * rot[o + 7] - 3.5f * l1k)) - 3;'// &
    &NL// &
    &'  for (uint id = thread_index_in_threadgroup; id < 576u; id += 512u) {'//NL// &
    &'    const int h = hlo + int(id % 24u);'//NL// &
    &'    const int k = klo + int(id / 24u);'//NL// &
    &'    float2 cc = float2(0.0f);'//NL// &
    &'    float qq = 0.0f;'//NL// &
    &'    if (h >= -NYQ && h <= NYQ && k >= -NYQ && k <= NYQ) {'//NL// &
    &'      const int i = pmap[(h + NYQ) + (2 * NYQ + 1) * (k + NYQ)];'//NL// &
    &'      if (i >= 0) {'//NL// &
    &'        const complex64_t cv = c[uint(i) + uint(NPIX) * uint(p)];'//NL// &
    &'        cc = float2(cv.real, cv.imag);'//NL// &
    &'        qq = q[uint(i) + uint(NPIX) * uint(p)];'//NL// &
    &'      }'//NL// &
    &'    }'//NL// &
    &'    pc[id] = cc;'//NL// &
    &'    pq[id] = qq;'//NL// &
    &'  }'//NL// &
    &'  threadgroup_barrier(mem_flags::mem_threadgroup);'//NL
! the voxel's projection on the plane and the 6 x 6 box of pixels whose window can cover it, k then h
character(len=*), parameter :: PULL_SCAN = &
    &'  if (act) {'//NL// &
    &'    const float hv = float(gx) * rot[o] + float(gy) * rot[o + 3] + float(gz) * rot[o + 6];'//NL// &
    &'    const float kv = float(gx) * rot[o + 1] + float(gy) * rot[o + 4] + float(gz) * rot[o + 7];'//NL// &
    &'    const int h0 = int(metal::floor(hv)) - 2;'//NL// &
    &'    const int k0 = int(metal::floor(kv)) - 2;'//NL// &
    &'    for (int k = k0; k < k0 + 6; ++k) {'//NL// &
    &'      for (int h = h0; h < h0 + 6; ++h) {'//NL
! the pixel's data from global memory (through the map of the disc's pixels) or from the staged patch
character(len=*), parameter :: PULL_PIXEL_GLOBAL = &
    &'        if (k < -NYQ || k > NYQ || h < -NYQ || h > NYQ) continue;'//NL// &
    &'        const int i = pmap[(h + NYQ) + (2 * NYQ + 1) * (k + NYQ)];'//NL// &
    &'        if (i < 0) continue;'//NL// &
    &'        const complex64_t cz0 = c[uint(i) + uint(NPIX) * uint(p)];'//NL// &
    &'        const float2 cv = float2(cz0.real, cz0.imag);'//NL// &
    &'        const float qv = q[uint(i) + uint(NPIX) * uint(p)];'//NL
character(len=*), parameter :: PULL_PIXEL_PATCH = &
    &'        const int ph = h - hlo;'//NL// &
    &'        const int pk = k - klo;'//NL// &
    &'        if (ph < 0 || ph >= 24 || pk < 0 || pk >= 24) continue;'//NL// &
    &'        const float2 cv = pc[ph + 24 * pk];'//NL// &
    &'        const float qv = pq[ph + 24 * pk];'//NL
! the probe's rule, its arithmetic written as the probe writes it: a pixel without data is skipped; its window's
! base per axis; skipped when its three h taps are negative; kept when its window covers the voxel; the voxel's
! weight and the three terms, added in registers
character(len=*), parameter :: PULL_TERMS = &
    &'        if (metal::fabs(cv.x) + metal::fabs(cv.y) <= 1.0e-10f && qv <= 1.0e-10f) continue;'//NL// &
    &'        const float h1 = float(h);'//NL// &
    &'        const float k1 = float(k);'//NL// &
    &'        int t0[3];'//NL// &
    &'        float w[3][3];'//NL// &
    &'        for (int a = 0; a < 3; ++a) {'//NL// &
    &'          const float loc = h1 * rot[o + 3 * a] + k1 * rot[o + 3 * a + 1];'//NL// &
    &'          const float b = metal::sign(loc) * metal::floor(metal::fabs(loc) + 0.5f);'//NL// &
    &'          t0[a] = int(b) - 1;'//NL// &
    &'          const float base = float(t0[a]) - loc;'//NL// &
    &'          float s = 0.0f;'//NL// &
    &'          for (int j = 0; j < 3; ++j) {'//NL// &
    &'            const float x = base + float(j);'//NL// &
    &'            const float qq = twoow * x;'//NL// &
    &'            const float u = metal::max(0.0f, 1.0f - qq * qq);'//NL// &
    &'            float pp = coef[14];'//NL// &
    &'            for (int cc = 13; cc >= 0; --cc) pp = pp * u + coef[cc];'//NL// &
    &'            w[a][j] = oneow * pp;'//NL// &
    &'            s += w[a][j];'//NL// &
    &'          }'//NL// &
    &'          for (int j = 0; j < 3; ++j) w[a][j] = w[a][j] / s;'//NL// &
    &'        }'//NL// &
    &'        if (t0[0] + 2 < 0) continue;'//NL// &
    &'        const int o0 = gx - t0[0];'//NL// &
    &'        const int o1 = gy - t0[1];'//NL// &
    &'        const int o2 = gz - t0[2];'//NL// &
    &'        if (o0 < 0 || o0 > 2 || o1 < 0 || o1 > 2 || o2 < 0 || o2 > 2) continue;'//NL// &
    &'        const float ww = w[0][o0] * w[1][o1] * w[2][o2];'//NL// &
    &'        const float fn = ww * 4.0f * om;'//NL// &
    &'        const float fd = ww * om;'//NL// &
    &'        ar += fn * cv.x;'//NL// &
    &'        ai += fn * cv.y;'//NL// &
    &'        ad += fd * qv;'//NL// &
    &'      }'//NL// &
    &'    }'//NL// &
    &'  }'//NL
! the voxel written once, as (re, im) of the numerator and the density
character(len=*), parameter :: PULL_WRITE = &
    &'}'//NL// &
    &'if (act) {'//NL// &
    &'  const uint v = gid.x + uint(NH) * (gid.y + uint(NK) * gid.z);'//NL// &
    &'  num[2 * v] = ar;'//NL// &
    &'  num[2 * v + 1] = ai;'//NL// &
    &'  dens[v] = ad;'//NL// &
    &'}'

contains

    ! ---- the probe ---------------------------------------------------------------------------------------------

    ! the group sum's kernel for ng groups of tg threads (tg a power of two, at most 1,024)
    function group_sum_spec( ng, tg ) result(spec)
        integer, intent(in) :: ng, tg
        type(mlx_custom_kernel_spec) :: spec
        spec%name          = 'forms_probe_group_sum'
        spec%source        = GROUP_LOAD//GROUP_BARRIER//GROUP_LEVEL//'  '//GROUP_BARRIER//GROUP_TAIL
        spec%input_names   = [character(len=1) :: 'x']
        spec%output_names  = [character(len=3) :: 'out']
        spec%grid          = [ng * tg, 1, 1]
        spec%threadgroup   = [tg, 1, 1]
        spec%output_shapes = [ng]
        spec%output_ranks  = [1]
        spec%output_dtypes = [MLX_DTYPES%float32]
    end function group_sum_spec

    ! the SIMD probe's kernel: n threads in threadgroups of tg, nout values per thread as (nout, n)
    function simd_probe_spec( n, tg, nout ) result(spec)
        integer, intent(in) :: n, tg, nout
        type(mlx_custom_kernel_spec) :: spec
        spec%name          = 'forms_probe_simd'
        spec%source        = SIMD_SOURCE
        spec%input_names   = [character(len=1) :: 'x']
        spec%output_names  = [character(len=3) :: 'res']
        spec%grid          = [n, 1, 1]
        spec%threadgroup   = [tg, 1, 1]
        spec%output_shapes = [nout, n]
        spec%output_ranks  = [2]
        spec%output_dtypes = [MLX_DTYPES%float32]
    end function simd_probe_spec

    ! a threadgroup array of nbytes bytes, one group of nthr threads
    function tgmem_probe_spec( nbytes, nthr ) result(spec)
        integer, intent(in) :: nbytes, nthr
        type(mlx_custom_kernel_spec) :: spec
        spec%name               = 'forms_probe_tgmem'
        spec%source             = TGMEM_SOURCE
        spec%input_names        = [character(len=1) :: 'x']
        spec%output_names       = [character(len=3) :: 'out']
        spec%grid               = [nthr, 1, 1]
        spec%threadgroup        = [nthr, 1, 1]
        spec%output_shapes      = [nthr]
        spec%output_ranks       = [1]
        spec%output_dtypes      = [MLX_DTYPES%float32]
        spec%template_int_names = [character(len=2) :: 'NF']
        spec%template_ints      = [nbytes / 4]
    end function tgmem_probe_spec

    ! ---- the tail ----------------------------------------------------------------------------------------------

    ! T1: the current tail's inputs and outputs, one SIMD group of 32 lanes per pair, two pairs a threadgroup
    function tail_simd_spec( spec_t ) result(spec)
        type(polarft_tile_spec), intent(in) :: spec_t
        type(mlx_custom_kernel_spec) :: spec
        integer                      :: np
        spec             = tail_spec(spec_t, .false.)
        np               = spec_t%rt * spec_t%bt
        spec%name        = 'forms_tail_simd'
        spec%source      = T1_HEAD//T1_MIN//T1_DRAW
        spec%grid        = [32 * np, 1, 1]
        spec%threadgroup = [64, 1, 1]
    end function tail_simd_spec

    ! T2: the current tail's source with each compensated step replaced by a plain sum; ok is false when the
    ! current source does not hold exactly the two steps it is derived from
    function tail_plain_spec( spec_t, ok ) result(spec)
        type(polarft_tile_spec), intent(in)  :: spec_t
        logical,                 intent(out) :: ok
        type(mlx_custom_kernel_spec)  :: spec
        character(len=:), allocatable :: src
        integer                       :: n, i
        spec = tail_spec(spec_t, .false.)
        src  = spec%source
        n    = 0
        do
            i = index(src, KAHAN_STEP)
            if( i == 0 ) exit
            src = src(1:i-1)//PLAIN_STEP//src(i+len(KAHAN_STEP):)
            n   = n + 1
        end do
        ok          = n == 2
        spec%name   = 'forms_tail_plain'
        spec%source = src
    end function tail_plain_spec

    ! ---- the reduction -----------------------------------------------------------------------------------------

    ! form 0 (serial), 1 (serial compensated) or 2 (threadgroup tree of tg threads) for ne evaluations of ns sums;
    ! inputs x (nt, ne) and y (ns, nt), output (ns, ne)
    function reduce_spec( form, ne, ns, tg ) result(spec)
        integer, intent(in) :: form, ne, ns, tg
        type(mlx_custom_kernel_spec) :: spec
        spec%input_names        = [character(len=1) :: 'x', 'y']
        spec%output_names       = [character(len=3) :: 'out']
        spec%output_shapes      = [ns, ne]
        spec%output_ranks       = [2]
        spec%output_dtypes      = [MLX_DTYPES%float32]
        spec%template_int_names = [character(len=3) :: 'NS', 'TG', 'NSG']
        spec%template_ints      = [ns, tg, tg / 32]
        spec%grid               = [ne, 1, 1]
        spec%threadgroup        = [min(ne, 64), 1, 1]
        select case( form )
            case( REDUCE_SERIAL )
                spec%name   = 'forms_reduce_serial'
                spec%source = R_HEAD//R0_BODY
            case( REDUCE_KAHAN )
                spec%name   = 'forms_reduce_kahan'
                spec%source = R_HEAD//R1_BODY
            case( REDUCE_TREE )
                spec%name        = 'forms_reduce_tree'
                spec%source      = R_HEAD//R2_PARTIALS//'threadgroup_barrier(mem_flags::mem_threadgroup);'//NL//R2_TOTAL
                spec%grid        = [ne * tg, 1, 1]
                spec%threadgroup = [tg, 1, 1]
        end select
    end function reduce_spec

    ! ---- sizes in an input -------------------------------------------------------------------------------------

    ! spec with its template integers read instead from an int32 input sz appended to the inputs: each template
    ! name becomes a constant of the body from sz in the templates' order; the source is otherwise unchanged
    function sizes_in_input( spec ) result(s1)
        type(mlx_custom_kernel_spec), intent(in) :: spec
        type(mlx_custom_kernel_spec)  :: s1
        character(len=:), allocatable :: head
        character(len=16)             :: buf
        character(len=32)             :: names(size(spec%input_names) + 1)
        integer                       :: i
        s1   = spec
        head = ''
        do i = 1, size(spec%template_int_names)
            write(buf, '(i0)') i - 1
            head = head//'const int '//trim(spec%template_int_names(i))//' = sz['//trim(buf)//'];'//NL
        end do
        names(1:size(spec%input_names)) = spec%input_names
        names(size(names))              = 'sz'
        s1%input_names = names
        s1%name        = trim(spec%name)//'_sizes'
        s1%source      = head//spec%source
        deallocate(s1%template_int_names, s1%template_ints)
    end function sizes_in_input

    ! ---- the selection -----------------------------------------------------------------------------------------

    ! E2 (simd false: one thread per particle) or E3 (one SIMD group per particle, threadgroups of 256) for the K
    ! best of npart columns; input t (nref, npart), outputs idx (int32) and val, (K, npart)
    function select_spec( simd, npart, k ) result(spec)
        logical, intent(in) :: simd
        integer, intent(in) :: npart, k
        type(mlx_custom_kernel_spec) :: spec
        spec%input_names        = [character(len=1) :: 't']
        spec%output_names       = [character(len=3) :: 'idx', 'val']
        spec%output_shapes      = [k, npart, k, npart]
        spec%output_ranks       = [2, 2]
        spec%output_dtypes      = [MLX_DTYPES%int32, MLX_DTYPES%float32]
        spec%template_int_names = [character(len=1) :: 'K']
        spec%template_ints      = [k]
        if( simd )then
            spec%name        = 'forms_select_simd'
            spec%source      = E3_SOURCE
            spec%grid        = [32 * npart, 1, 1]
            spec%threadgroup = [256, 1, 1]
        else
            spec%name        = 'forms_select_thread'
            spec%source      = E2_SOURCE
            spec%grid        = [npart, 1, 1]
            spec%threadgroup = [min(npart, 64), 1, 1]
        endif
    end function select_spec

    ! ---- the insertion as a pull ---------------------------------------------------------------------------------

    ! D1 (staged false: each pixel read from global memory) or D2 (each reaching plane's patch staged in threadgroup
    ! memory between two barriers) on the voxel grid (nh, nk, nk); inputs the disc's pixel map, the planes' rotations,
    ! weights and data, the window's coefficients and par (7 int32); outputs the numerator (2, nvox) and density
    function insert_pull_spec( staged, nh, nk ) result(spec)
        logical, intent(in) :: staged
        integer, intent(in) :: nh, nk
        type(mlx_custom_kernel_spec) :: spec
        integer                      :: nvox
        nvox = nh * nk * nk
        spec%input_names   = [character(len=5) :: 'pmap', 'rot', 'omega', 'c', 'q', 'coef', 'par']
        spec%output_names  = [character(len=4) :: 'num', 'dens']
        spec%output_shapes = [2, nvox, nvox]
        spec%output_ranks  = [2, 1]
        spec%output_dtypes = [MLX_DTYPES%float32, MLX_DTYPES%float32]
        spec%grid          = [8 * ((nh + 7) / 8), 8 * ((nk + 7) / 8), 8 * ((nk + 7) / 8)]
        spec%threadgroup   = [8, 8, 8]
        if( staged )then
            spec%name   = 'forms_insert_staged'
            spec%source = 'threadgroup float2 pc[576];'//NL//'threadgroup float pq[576];'//NL//PULL_HEAD//PULL_PLANE// &
                &PULL_STAGE//PULL_SCAN//PULL_PIXEL_PATCH//PULL_TERMS// &
                &'  threadgroup_barrier(mem_flags::mem_threadgroup);'//NL//PULL_WRITE
        else
            spec%name   = 'forms_insert_pull'
            spec%source = PULL_HEAD//PULL_PLANE//PULL_SCAN//PULL_PIXEL_GLOBAL//PULL_TERMS//PULL_WRITE
        endif
    end function insert_pull_spec

end module mlxf_bench_kernel_forms_src
