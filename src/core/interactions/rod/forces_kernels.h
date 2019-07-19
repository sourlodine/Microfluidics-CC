#pragma once

#include "real.h"
#include "bisegment.h"

#include <core/pvs/rod_vector.h>
#include <core/pvs/views/rv.h>
#include <core/utils/cpu_gpu_defines.h>
#include <core/utils/cuda_common.h>
#include <core/utils/cuda_rng.h>

struct GPU_RodBoundsParameters
{
    float lcenter, lcross, ldiag, lring;
    float ksCenter, ksFrame;
};

namespace RodForcesKernels
{

// elastic force exerted from p1 to p0
__device__ inline real3 fbound(const real3& r0, const real3& r1, const float ks, float l0)
{
    auto dr = r1 - r0;
    auto l = length(dr);
    auto xi = (l - l0);
    auto linv = 1.0_r / l;

    auto fmagn = ks * xi * (0.5_r * xi + l);
    
    return (linv * fmagn) * dr;
}

__global__ void computeRodBoundForces(RVview view, GPU_RodBoundsParameters params)
{
    const int i = threadIdx.x + blockIdx.x * blockDim.x;
    const int rodId     = i / view.nSegments;
    const int segmentId = i % view.nSegments;
    const int start = view.objSize * rodId + segmentId * 5;

    if (rodId     >= view.nObjects ) return;
    if (segmentId >= view.nSegments) return;

    auto r0 = fetchPosition(view, start + 0);
    auto u0 = fetchPosition(view, start + 1);
    auto u1 = fetchPosition(view, start + 2);
    auto v0 = fetchPosition(view, start + 3);
    auto v1 = fetchPosition(view, start + 4);
    auto r1 = fetchPosition(view, start + 5);

    real3 fr0{0._r, 0._r, 0._r}, fr1{0._r, 0._r, 0._r};
    real3 fu0{0._r, 0._r, 0._r}, fu1{0._r, 0._r, 0._r};
    real3 fv0{0._r, 0._r, 0._r}, fv1{0._r, 0._r, 0._r};

#define BOUND(a, b, k, l) do {                          \
        auto f = fbound(a, b, params. k, params. l);    \
        f##a += f;                                      \
        f##b -= f;                                      \
    } while(0)

    BOUND(r0, u0, ksFrame, ldiag);
    BOUND(r0, u1, ksFrame, ldiag);
    BOUND(r0, v0, ksFrame, ldiag);
    BOUND(r0, v1, ksFrame, ldiag);

    BOUND(r1, u0, ksFrame, ldiag);
    BOUND(r1, u1, ksFrame, ldiag);
    BOUND(r1, v0, ksFrame, ldiag);
    BOUND(r1, v1, ksFrame, ldiag);

    BOUND(u0, v0, ksFrame, lring);
    BOUND(v0, u1, ksFrame, lring);
    BOUND(u1, v1, ksFrame, lring);
    BOUND(v1, u0, ksFrame, lring);

    BOUND(u0, u1, ksFrame, lcross);
    BOUND(v0, v1, ksFrame, lcross);

    BOUND(r0, r1, ksCenter, lcenter);

#undef BOUND
    
    atomicAdd(view.forces + start + 0, make_float3(fr0));
    atomicAdd(view.forces + start + 1, make_float3(fu0));
    atomicAdd(view.forces + start + 2, make_float3(fu1));
    atomicAdd(view.forces + start + 3, make_float3(fv0));
    atomicAdd(view.forces + start + 4, make_float3(fv1));
    atomicAdd(view.forces + start + 5, make_float3(fr1));
}

template <int Nstates>
__device__ inline int getState(const RVview& view, int i)
{
    if (Nstates > 1) return view.states[i];
    else             return 0;
}

template <int Nstates>
__global__ void computeRodBiSegmentForces(RVview view, GPU_RodBiSegmentParameters<Nstates> params, bool saveEnergies)
{
    constexpr int stride = 5;
    const int i = threadIdx.x + blockIdx.x * blockDim.x;
    const int nBiSegments = view.nSegments - 1;
    const int rodId       = i / nBiSegments;
    const int biSegmentId = i % nBiSegments;
    const int start = view.objSize * rodId + biSegmentId * stride;

    if (rodId       >= view.nObjects ) return;
    if (biSegmentId >= nBiSegments   ) return;

    const BiSegment<Nstates> bisegment(view, start);

    real3 fr0, fr2, fpm0, fpm1;
    fr0 = fr2 = fpm0 = fpm1 = make_real3(0.0_r);

    const int state = getState<Nstates>(view, i);
    
    bisegment.computeBendingForces(state, params, fr0, fr2, fpm0, fpm1);
    bisegment.computeTwistForces  (state, params, fr0, fr2, fpm0, fpm1);

    // by conservation of momentum
    auto fr1  = -(fr0 + fr2);
    auto fpp0 = -fpm0;
    auto fpp1 = -fpm1;
    
    atomicAdd(view.forces + start + 0 * stride, make_float3(fr0));
    atomicAdd(view.forces + start + 1 * stride, make_float3(fr1));
    atomicAdd(view.forces + start + 2 * stride, make_float3(fr2));

    atomicAdd(view.forces + start +          1, make_float3(fpm0));
    atomicAdd(view.forces + start +          2, make_float3(fpp0));
    atomicAdd(view.forces + start + stride + 1, make_float3(fpm1));
    atomicAdd(view.forces + start + stride + 2, make_float3(fpp1));

    if (saveEnergies) view.energies[i] = bisegment.computeEnergy(state, params);
}

__global__ void computeRodCurvatureSmoothing(RVview view, const real kbi,
                                             const float4 *kappa, const float2 *tau_l)
{
    constexpr int stride = 5;
    const int i = threadIdx.x + blockIdx.x * blockDim.x;
    const int nBiSegments = view.nSegments - 1;
    const int rodId       = i / nBiSegments;
    const int biSegmentId = i % nBiSegments;
    const int start = view.objSize * rodId + biSegmentId * stride;

    if (rodId       >= view.nObjects ) return;
    if (biSegmentId >= nBiSegments   ) return;

    const BiSegment<0> bisegment(view, start);

    real3 gradr0x, gradr0y, gradr0z;
    real3 gradr2x, gradr2y, gradr2z;
    real3 gradpm0x, gradpm0y, gradpm0z;
    real3 gradpm1x, gradpm1y, gradpm1z;

    bisegment.computeCurvaturesGradients(gradr0x, gradr0y,
                                         gradr2x, gradr2y,
                                         gradpm0x, gradpm0y,
                                         gradpm1x, gradpm1y);

    bisegment.computeTorsionGradients(gradr0z, gradr2z,
                                      gradpm0z, gradpm1z);

    const auto k  = kappa[i];
    const auto kl = biSegmentId > 0               ? kappa[i-1] : make_real4(0._r);
    const auto kr = biSegmentId < (nBiSegments-1) ? kappa[i+1] : make_real4(0._r);

    const auto tl  = tau_l[i];
    const auto tll = biSegmentId > 0               ? tau_l[i-1] : make_real2(0._r);
    const auto tlr = biSegmentId < (nBiSegments-1) ? tau_l[i+1] : make_real2(0._r);

    const real3 dOmegal = biSegmentId > 0 ?
        real3 {k.x - kl.x, k.y - kl.y, tl.x - tll.x} : real3 {0._r, 0._r, 0._r};

    const real3 dOmegar = biSegmentId > (nBiSegments-1) ?
        real3 {kr.x - k.x, kr.y - k.y, tlr.x - tl.x} : real3 {0._r, 0._r, 0._r};

    const real llinv = 1.0_r / tll.y;
    const real linv  = 1.0_r / tl.y;

    const real coeffl = biSegmentId > 0 ? 0.5_r * kbi / tll.y : 0._r;
    const real coeffm = 0.5_r * kbi / tl.y;

    auto applyGrad = [](real3 gx, real3 gy, real3 gz, real3 v) -> real3
    {
        return {gx.x * v.x + gy.x * v.y + gz.x * v.z,
                gx.y * v.x + gy.y * v.y + gz.y * v.z,
                gx.z * v.x + gy.z * v.y + gz.z * v.z};
    };
    
    real3 fr0 =
        coeffl * applyGrad(gradr0x, gradr0y, gradr0z, dOmegal) -
        coeffm * applyGrad(gradr0x, gradr0y, gradr0z, dOmegar);

    real3 fr2 =
        coeffl * applyGrad(gradr2x, gradr2y, gradr2z, dOmegal) -
        coeffm * applyGrad(gradr2x, gradr2y, gradr2z, dOmegar);

    const real3 fpm0 = 
        coeffl * applyGrad(gradpm0x, gradpm0y, gradpm0z, dOmegal) -
        coeffm * applyGrad(gradpm0x, gradpm0y, gradpm0z, dOmegar);

    const real3 fpm1 = 
        coeffl * applyGrad(gradpm1x, gradpm1y, gradpm1z, dOmegal) -
        coeffm * applyGrad(gradpm1x, gradpm1y, gradpm1z, dOmegar);

    // contribution of l
    if (biSegmentId < nBiSegments - 1)
    {
        const auto coeff = 0.5_r * kbi * dot(dOmegar, dOmegar);
        fr0 -= coeff * bisegment.t0;
        fr2 += coeff * bisegment.t1;
    }
    
    // by conservation of momentum
    auto fr1  = -(fr0 + fr2);
    auto fpp0 = -fpm0;
    auto fpp1 = -fpm1;
    
    atomicAdd(view.forces + start + 0 * stride, make_float3(fr0));
    atomicAdd(view.forces + start + 1 * stride, make_float3(fr1));
    atomicAdd(view.forces + start + 2 * stride, make_float3(fr2));

    atomicAdd(view.forces + start +          1, make_float3(fpm0));
    atomicAdd(view.forces + start +          2, make_float3(fpp0));
    atomicAdd(view.forces + start + stride + 1, make_float3(fpm1));
    atomicAdd(view.forces + start + stride + 2, make_float3(fpp1));
}


} // namespace RodForcesKernels
