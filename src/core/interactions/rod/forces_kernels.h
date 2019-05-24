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
__global__ void computeRodBiSegmentForces(RVview view, GPU_RodBiSegmentParameters<Nstates> params)
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
    int state = 0;

    if (Nstates > 1)
    {
        real E = bisegment.computeEnergy(state, params);
        
        #pragma unroll
        for (int s = 1; s < Nstates; ++s)
        {
            real Es = bisegment.computeEnergy(state, params);
            if (Es < E)
            {
                E = Es;
                state = s;
            }
        }
    }
    
    fr0 = fr2 = fpm0 = fpm1 = make_real3(0.0_r);
    
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
}


} // namespace RodForcesKernels
