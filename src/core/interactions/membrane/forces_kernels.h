#pragma once

#include "common.h"

namespace MembraneForcesKernels
{

static constexpr float forceCap = 1500.f;

struct GPU_RBCparameters
{
    float scale; /* hack for stress free TODO? */
    float gammaC, gammaT;
    float mpow, l0, x0, ks;
    float area0, totArea0, totVolume0;
    float ka0, kv0, kd0;

    bool fluctuationForces;
    float seed, sigma_rnd;
};

__device__ inline float3 _ftriangle(const float3 v1, const float3 v2, const float3 v3,
                                    const float area0, const float totArea, GPU_RBCparameters parameters)
{
    float3 x21 = v2 - v1;
    float3 x32 = v3 - v2;
    float3 x31 = v3 - v1;

    float3 normal = cross(x21, x31);

    float area = 0.5f * length(normal);
    float area_1 = 1.0f / area;

    // TODO: optimize computations here
    float coefArea = -0.25f * (
            parameters.ka0 * (totArea - parameters.totArea0) * area_1
          + parameters.kd0 * (area - area0) / (area * area0) );

    float3 fArea = coefArea * cross(normal, x32);

    return fArea;
}

__device__ inline float3 _fvolume(float3 v1, float3 v2, float3 v3, float totVolume, GPU_RBCparameters parameters)
{
    float coeff = parameters.kv0 * (totVolume - parameters.totVolume0);
    return coeff * cross(v3, v2);
}


__device__ inline float3 _fbond(const float3 v1, const float3 v2, const float l0, GPU_RBCparameters parameters)
{
    float r = max(length(v2 - v1), 1e-5f);
    float lmax     = l0 / parameters.x0;
    float inv_lmax = parameters.x0 / l0;

    auto wlc = [parameters, inv_lmax] (float x) {
        return parameters.ks * inv_lmax * (4.0f*x*x - 9.0f*x + 6.0f) / ( 4.0f*sqr(1.0f - x) );
    };

    const float IbforceI_wlc = wlc( min(lmax - 1e-6f, r) * inv_lmax );

    const float kp = wlc( l0 * inv_lmax ) * fastPower(l0, parameters.mpow+1);

    const float IbforceI_pow = -kp / (fastPower(r, parameters.mpow+1));

    const float IfI = min(forceCap, max(-forceCap, IbforceI_wlc + IbforceI_pow));

    return IfI * (v2 - v1);
}

__device__ inline float3 _fvisc(Particle p1, Particle p2, GPU_RBCparameters parameters)
{
    const float3 du = p2.u - p1.u;
    const float3 dr = p1.r - p2.r;

    return du*parameters.gammaT + dr * parameters.gammaC*dot(du, dr) / dot(dr, dr);
}

__device__ inline float3 _ffluct(float3 v1, float3 v2, int i1, int i2, GPU_RBCparameters parameters)
{
    if (!parameters.fluctuationForces)
        return make_float3(0.0f);

    float2 rnd = Saru::normal2(parameters.seed, min(i1, i2), max(i1, i2));
    float3 x21 = v2 - v1;
    return (rnd.x * parameters.sigma_rnd / length(x21)) * x21;
}

__device__ inline float3 bondTriangleForce(
        bool stressFree,
        Particle p, int locId, int rbcId,
        const OVviewWithAreaVolume& view,
        const MembraneMeshView& mesh,
        const GPU_RBCparameters& parameters)
{
    float3 f = make_float3(0.0f);
    const int startId = mesh.maxDegree * locId;
    const int degree = mesh.degrees[locId];

    int idv0 = rbcId * mesh.nvertices + locId;
    int idv1 = rbcId * mesh.nvertices + mesh.adjacent[startId];
    Particle p1(view.particles, idv1);

#pragma unroll 2
    for (int i = 1; i <= degree; i++)
    {
        int idv2 = rbcId * mesh.nvertices + mesh.adjacent[startId + (i % degree)];

        Particle p2(view.particles, idv2);

        float l0 = stressFree ? mesh.initialLengths[startId + i-1] : parameters.l0;
        float a0 = stressFree ? mesh.initialAreas  [startId + i-1] : parameters.area0;

        if (stressFree) {
            l0 *= parameters.scale;
            a0 *= parameters.scale * parameters.scale;
        }

        float totArea   = view.area_volumes[rbcId].x;
        float totVolume = view.area_volumes[rbcId].y;
        
        f +=  _ftriangle (p.r, p1.r, p2.r, a0, totArea, parameters)
            + _fvolume   (p.r, p1.r, p2.r, totVolume, parameters)
            + _fbond     (p.r, p1.r, l0, parameters)
            + _fvisc     (p,   p1,       parameters)
            + _ffluct    (p.r, p1.r, idv0, idv1, parameters);

        idv1 = idv2;
        p1 = p2;
    }

    return f;
}

template <class DihedralInteraction>
__device__ inline float3 dihedralForce(int locId, int rbcId,
                                       const typename DihedralInteraction::ViewType& view,
                                       DihedralInteraction& dihedralInteraction,
                                       const MembraneMeshView& mesh)
{
    const int offset = rbcId * mesh.nvertices;

    const int startId = mesh.maxDegree * locId;
    const int degree = mesh.degrees[locId];

    int idv0 = offset + locId;
    int idv1 = offset + mesh.adjacent[startId];
    int idv2 = offset + mesh.adjacent[startId+1];

    auto v0 = dihedralInteraction.fetchVertex(view, idv0);
    auto v1 = dihedralInteraction.fetchVertex(view, idv1);
    auto v2 = dihedralInteraction.fetchVertex(view, idv2);

    //       v3
    //     /   \
    //   v2 --> v0
    //     \   /
    //       V
    //       v1

    float3 f0 = make_float3(0,0,0);

    dihedralInteraction.computeCommon(view, rbcId);

#pragma unroll 2
    for (int i = 0; i < degree; i++)
    {
        float3 f1;
        int idv3 = offset + mesh.adjacent[startId + (i+2) % degree];        

        auto v3 = dihedralInteraction.fetchVertex(view, idv3);

        f0 += dihedralInteraction(v0, v1, v2, v3, f1);

        atomicAdd(view.forces + idv1, f1);
            
        v1   = v2  ; v2   = v3  ;
        idv1 = idv2; idv2 = idv3;
    }
    return f0;
}

template <class DihedralInteraction>
__global__ void computeMembraneForces(bool stressFree, DihedralInteraction dihedralInteraction,
                                      typename DihedralInteraction::ViewType dihedralView,
                                      OVviewWithAreaVolume view,
                                      MembraneMeshView mesh,
                                      GPU_RBCparameters parameters)
{
    // RBC particles are at the same time mesh vertices
    assert(view.objSize == mesh.nvertices);

    const int pid = threadIdx.x + blockDim.x * blockIdx.x;
    const int locId = pid % mesh.nvertices;
    const int rbcId = pid / mesh.nvertices;

    if (pid >= view.nObjects * mesh.nvertices) return;

    Particle p(view.particles, pid);

    float3 f;
    f  = bondTriangleForce(stressFree, p, locId, rbcId, view, mesh, parameters);
    f += dihedralForce(locId, rbcId, dihedralView, dihedralInteraction, mesh);

    atomicAdd(view.forces + pid, f);
}

} // namespace MembraneInteractionKernels
