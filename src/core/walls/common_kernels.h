#pragma once

#include <core/celllist.h>
#include <core/pvs/views/pv.h>
#include <core/utils/cuda_common.h>
#include <core/utils/cuda_rng.h>
#include <core/utils/root_finder.h>

namespace BounceKernels
{

template <typename InsideWallChecker>
__device__ inline float3 rescue(float3 candidate, float dt, float tol, int seed, const InsideWallChecker& checker)
{
    const int maxIters = 100;
    const float factor = 5.0f * dt;

    for (int i = 0; i < maxIters; i++)
    {
        const float v = checker(candidate);
        if (v < -tol) break;

        float3 rndShift;
        rndShift.x = Saru::mean0var1(candidate.x - floorf(candidate.x), seed+i, seed*seed);
        rndShift.y = Saru::mean0var1(rndShift.x,                        seed+i, seed*seed);
        rndShift.z = Saru::mean0var1(rndShift.y,                        seed+i, seed*seed);

        if (checker(candidate + factor * rndShift) < v)
            candidate += factor * rndShift;
    }

    return candidate;
}

template <typename InsideWallChecker, typename VelocityField>
__global__ void sdfBounce(PVviewWithOldParticles view, CellListInfo cinfo,
                          const int *wallCells, const int nWallCells, const float dt,
                          const InsideWallChecker checker,
                          const VelocityField velField,
                          double3 *totalForce)
{
    const float insideTolerance = 2e-6f;
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;

    float3 localForce{0.f, 0.f, 0.f};
    
    if (tid < nWallCells)
    {
        const int cid = wallCells[tid];
        const int pstart = cinfo.cellStarts[cid];
        const int pend   = cinfo.cellStarts[cid+1];

        for (int pid = pstart; pid < pend; pid++)
        {
            Particle p(view.readParticle(pid));
            if (checker(p.r) <= -insideTolerance) continue;

            const auto rOld = view.readOldPosition(pid);
            const float3 dr = p.r - rOld;

            constexpr RootFinder::Bounds limits {0.f, 1.f};
            const float alpha = RootFinder::linearSearch([=] (float lambda)
            {
                return checker(rOld + dr*lambda) + insideTolerance;
            }, limits);

            float3 candidate = (alpha >= limits.lo) ? rOld + alpha * dr : rOld;
            candidate = rescue(candidate, dt, insideTolerance, p.i1, checker);

            const float3 uWall = velField(p.r);
            const float3 unew = 2*uWall - p.u;

            localForce += (p.u - unew) * (view.mass / dt); // force exerted by the particle on the wall

            p.r = candidate;
            p.u = unew;
                           
            view.writeParticle(pid, p);
        }        
    }

    localForce = warpReduce(localForce, [](float a, float b){return a+b;});
    
    if ((laneId() == 0) && (length(localForce) > 1e-8f))
        atomicAdd(totalForce, make_double3(localForce));

}

} // namespace BounceKernels
