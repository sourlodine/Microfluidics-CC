#pragma once

#include "common.h"

#include <core/celllist.h>
#include <core/pvs/views/ov.h>
#include <core/utils/cuda_common.h>
#include <core/utils/cuda_rng.h>
#include <core/utils/root_finder.h>

namespace MeshBounceKernels
{

struct Triangle
{
    float3 v0, v1, v2;
};

using TriangleTable = CollisionTable<int2>;

__device__ static inline Triangle readTriangle(const float4 *vertices, int startId, int3 trid)
{
    auto addr = vertices + startId;
    return {
        make_float3( addr[trid.x] ),
        make_float3( addr[trid.y] ),
        make_float3( addr[trid.z] ) };
}



__device__ static inline bool segmentTriangleQuickCheck(Triangle trNew, Triangle trOld, float3 xNew, float3 xOld)
{
    const float3 v0 = trOld.v0;
    const float3 v1 = trOld.v1;
    const float3 v2 = trOld.v2;

    const float3 dx  = xNew - xOld;
    const float3 dv0 = trNew.v0 - v0;
    const float3 dv1 = trNew.v1 - v1;
    const float3 dv2 = trNew.v2 - v2;

    // Distance to the triangle plane
    auto F = [=] (float t) {
        const float3 v0t = v0 + t*dv0;
        const float3 v1t = v1 + t*dv1;
        const float3 v2t = v2 + t*dv2;

        const float3 nt = normalize(cross(v1t-v0t, v2t-v0t));
        const float3 xt = xOld + t*dx;
        return  dot( xt - v0t, nt );
    };

    // d / dt (non normalized Distance)
    auto F_prime = [=] (float t) {
        const float3 v0t = v0 + t*dv0;
        const float3 v1t = v1 + t*dv1;
        const float3 v2t = v2 + t*dv2;

        const float3 nt = cross(v1t-v0t, v2t-v0t);

        const float3 xt = xOld + t*dx;
        return dot(dx-dv0, nt) + dot(xt-v0t, cross(dv1-dv0, v2t-v0t) + cross(v1t-v0t, dv2-dv0));
    };

    const auto F0 = F(0.0f);
    const auto F1 = F(1.0f);

    // assume that particles don t move more than this distance every time step
    constexpr float tolDistance = 0.1;
    
    if (fabsf(F0) > tolDistance && fabsf(F1) > tolDistance)
        return false;
    
    if (F0 * F1 < 0.0f)
        return true;

    // XXX: This is not always correct
    if (F_prime(0.0f) * F_prime(1.0f) >= 0.0f)
        return false;

    return true;
}

__device__ static inline void findBouncesInCell(int pstart, int pend, int globTrid,
                                                Triangle tr, Triangle trOld,
                                                PVviewWithOldParticles pvView,
                                                MeshView mesh, TriangleTable triangleTable)
{

#pragma unroll 2
    for (int pid = pstart; pid < pend; pid++)
    {
        Particle p;
        pvView.readPosition   (p,    pid);
        const auto rOld = pvView.readOldPosition(pid);

        if (segmentTriangleQuickCheck(tr, trOld, p.r, rOld))
            triangleTable.push_back({pid, globTrid});
    }
}

__global__ void findBouncesInMesh(OVviewWithNewOldVertices objView,
                                  PVviewWithOldParticles pvView,
                                  MeshView mesh, CellListInfo cinfo,
                                  TriangleTable triangleTable)
{
    // About maximum distance a particle can cover in one step
    constexpr float tol = 0.2f;

    // One THREAD per triangle
    const int gid = blockIdx.x * blockDim.x + threadIdx.x;
    const int objId = gid / mesh.ntriangles;
    const int trid  = gid % mesh.ntriangles;
    if (objId >= objView.nObjects) return;

    const int3 triangle = mesh.triangles[trid];
    const Triangle tr =    readTriangle(objView.vertices    , mesh.nvertices*objId, triangle);
    const Triangle trOld = readTriangle(objView.old_vertices, mesh.nvertices*objId, triangle);

    const float3 lo = fmin_vec(trOld.v0, trOld.v1, trOld.v2, tr.v0, tr.v1, tr.v2);
    const float3 hi = fmax_vec(trOld.v0, trOld.v1, trOld.v2, tr.v0, tr.v1, tr.v2);

    const int3 cidLow  = cinfo.getCellIdAlongAxes(lo - tol);
    const int3 cidHigh = cinfo.getCellIdAlongAxes(hi + tol);

    int3 cid3;
#pragma unroll 2
    for (cid3.z = cidLow.z; cid3.z <= cidHigh.z; cid3.z++)
        for (cid3.y = cidLow.y; cid3.y <= cidHigh.y; cid3.y++)
            {
                cid3.x = cidLow.x;
                const int cidLo = max(cinfo.encode(cid3), 0);

                cid3.x = cidHigh.x;
                const int cidHi = min(cinfo.encode(cid3)+1, cinfo.totcells);

                const int pstart = cinfo.cellStarts[cidLo];
                const int pend   = cinfo.cellStarts[cidHi];

                findBouncesInCell(pstart, pend, gid, tr, trOld, pvView, mesh, triangleTable);
            }
}

//=================================================================================================================
// Filter the collisions better
//=================================================================================================================


__device__ static inline bool isInside(Triangle tr, float3 p)
{
    const float edgeTolerance = 1e-18f;

    auto signedArea2 = [] (float3 a, float3 b, float3 c, float3 direction) {
        const auto n = cross(a-b, a-c);
        const auto sign = dot(n, direction);

        const auto S2 = dot(n, n);
        return (sign >= 0.0f) ? S2 : -S2;
    };

    const float3 n = cross(tr.v1-tr.v0, tr.v2-tr.v0);

    const float s0 = signedArea2(tr.v0, tr.v1, p, n);
    const float s1 = signedArea2(tr.v1, tr.v2, p, n);
    const float s2 = signedArea2(tr.v2, tr.v0, p, n);


    return (s0 > -edgeTolerance && s1 > -edgeTolerance && s2 > -edgeTolerance);
}


__device__ static inline void sort3(RootFinder::RootInfo v[3])
{
    auto swap = [] (RootFinder::RootInfo& a, RootFinder::RootInfo& b)
    {
        const auto tmp = a;
        a = b;
        b = tmp;
    };

    if (v[0].x > v[1].x) swap(v[0], v[1]);
    if (v[0].x > v[2].x) swap(v[0], v[2]);
    if (v[1].x > v[2].x) swap(v[1], v[2]);
}

static constexpr float noCollision {-1.f};

struct IntersectionInfo
{
    float alpha; // "time" (0.0 to 1.0) of the segment - moving triangle intersection
    float3 point;
    Triangle triangle;
    float sign;    
};

__device__ static inline IntersectionInfo
intersectSegmentWithTriangle(Triangle trNew, Triangle trOld,
                             float3 xNew, float3 xOld)
{
    constexpr float tol        {2e-6f};
    constexpr float leftLimit  {0.0f};
    constexpr float rightLimit {1.0f};
    constexpr float epsilon    {1e-5f};

    IntersectionInfo info;
    
    const float3 v0 = trOld.v0;
    const float3 v1 = trOld.v1;
    const float3 v2 = trOld.v2;

    const float3 dx  = xNew - xOld;
    const float3 dv0 = trNew.v0 - v0;
    const float3 dv1 = trNew.v1 - v1;
    const float3 dv2 = trNew.v2 - v2;


    // precompute scaling factor
    auto n = cross(trNew.v1-trNew.v0,
                   trNew.v2-trNew.v0);
    const float n_1 = rsqrtf(dot(n, n));

    // Distance to a triangle
    auto F = [=] (float t) {
        const float3 v0t = v0 + t*dv0;
        const float3 v1t = v1 + t*dv1;
        const float3 v2t = v2 + t*dv2;

        const float3 xt = xOld + t*dx;
        return  n_1 * dot( xt - v0t, cross(v1t-v0t, v2t-v0t) );
    };

    // d / dt (Distance)
    auto F_prime = [=] (float t)
    {
        const float3 v0t = v0 + t*dv0;
        const float3 v1t = v1 + t*dv1;
        const float3 v2t = v2 + t*dv2;

        const float3 nt = cross(v1t-v0t, v2t-v0t);

        const float3 xt = xOld + t*dx;
        return  n_1 * ( dot(dx-dv0, nt) + dot(xt-v0t, cross(dv1-dv0, v2t-v0t) + cross(v1t-v0t, dv2-dv0)) );
    };

    // Has side-effects!!
    auto checkIfInside = [&] (float alpha)
    {
        info.point = xOld + alpha*dx;

        info.triangle.v0 = v0 + alpha*dv0;
        info.triangle.v1 = v1 + alpha*dv1;
        info.triangle.v2 = v2 + alpha*dv2;

        info.sign = -F_prime(alpha);

        return isInside(info.triangle, info.point);
    };

    RootFinder::RootInfo roots[3];
    roots[0] = RootFinder::newton(F, F_prime, leftLimit);
    roots[2] = RootFinder::newton(F, F_prime, rightLimit);

    auto validRoot = [](RootFinder::RootInfo root)
    {
        return root.x >= leftLimit
            && root.x <= rightLimit
            && fabsf(root.val) < tol;
    };

    float left, right;

    if (F(leftLimit) * F(rightLimit) < 0.0f)
    {
        // Three roots
        if (validRoot(roots[0]) && validRoot(roots[2]))
        {
            left  = roots[0].x + epsilon/fabsf(F_prime(roots[0].x));
            right = roots[2].x - epsilon/fabsf(F_prime(roots[2].x));
        }
        else // One root
        {
            left  = leftLimit;
            right = rightLimit;
        }
    }
    else  // Maybe two roots
    {
        RootFinder::RootInfo newtonRoot {RootFinder::invalidRoot};

        if (validRoot(roots[0])) newtonRoot = roots[0];
        if (validRoot(roots[2])) newtonRoot = roots[2];

        if (newtonRoot == RootFinder::invalidRoot)
        {
            left  = leftLimit;
            right = rightLimit;
        }
        else if (F(leftLimit) * F_prime(newtonRoot.x) > 0.0f)
        {
            left  = leftLimit;
            right = newtonRoot.x - epsilon/fabsf(F_prime(newtonRoot.x));
        }
        else
        {
            left  = newtonRoot.x + epsilon/fabsf(F_prime(newtonRoot.x));
            right = rightLimit;
        }
    }

    roots[1] = RootFinder::linearSearchVerbose(F, RootFinder::Bounds{left, right});

    sort3(roots);

    if      (validRoot(roots[0]) && checkIfInside(roots[0].x)) info.alpha = roots[0].x;
    else if (validRoot(roots[1]) && checkIfInside(roots[1].x)) info.alpha = roots[1].x;
    else if (validRoot(roots[2]) && checkIfInside(roots[2].x)) info.alpha = roots[2].x;
    else                                                       info.alpha = noCollision;
    
    return info;
}

__global__
void refineCollisions(OVviewWithNewOldVertices objView,
                      PVviewWithOldParticles pvView,
                      MeshView mesh,
                      int nCoarseCollisions, int2 *coarseTable,
                      TriangleTable fineTable,
                      int *collisionTimes)
{
    const int gid = blockIdx.x * blockDim.x + threadIdx.x;
    if (gid >= nCoarseCollisions) return;

    const int2 pid_trid = coarseTable[gid];
    const int pid = pid_trid.x;

    const Particle p (pvView.readParticle   (pid));
    const auto rOld = pvView.readOldPosition(pid);

    const int trid  = pid_trid.y % mesh.ntriangles;
    const int objId = pid_trid.y / mesh.ntriangles;

    const int3 triangle = mesh.triangles[trid];
    const Triangle tr =    readTriangle(objView.vertices    , mesh.nvertices*objId, triangle);
    const Triangle trOld = readTriangle(objView.old_vertices, mesh.nvertices*objId, triangle);

    const auto info = intersectSegmentWithTriangle(tr, trOld, p.r, rOld);

    if (info.alpha == noCollision) return;

    atomicMax(collisionTimes+pid, __float_as_int(1.0f - info.alpha));
    fineTable.push_back(pid_trid);
}



//=================================================================================================================
// Perform the damn collisions
//=================================================================================================================


// p is assumed to be in the a-b-c plane
// a lot more precise method that the one solving a linear system
__device__ static inline
float3 barycentric(Triangle tr, float3 p)
{
    auto signedArea = [] (float3 a, float3 b, float3 c, float3 direction) {
        const auto n = cross(a-b, a-c);
        const auto sign = dot(n, direction);

        const auto S = length(n);
        return (sign >= 0.0f) ? S : -S;
    };

    const auto n = cross(tr.v0-tr.v1, tr.v0-tr.v2);
    const auto s0_1 = rsqrtf(dot(n, n));

    const auto s1 = signedArea(tr.v0, tr.v1, p, n);
    const auto s2 = signedArea(tr.v1, tr.v2, p, n);
    const auto s3 = signedArea(tr.v2, tr.v0, p, n);

    return make_float3(s2, s3, s1) * s0_1;
}

// Particle with mass M and velocity U0 hits triangle tr (v0, v1, v2)
// into point O. Its new velocity is Unew.
// Vertex masses are m. Treated as rigid and stationary,
// what are the vertex forces induced by the collision?
__device__ static inline
void triangleForces(Triangle tr, float m,
                    float3 O_barycentric, float3 Uold, float3 Unew, float M,
                    float dt,
                    float3& f0, float3& f1, float3& f2)
{
    constexpr float tol = 1e-5f;
    constexpr float oneThrird = 1.0 / 3.0;

    auto len2 = [] (float3 x) {
        return dot(x, x);
    };

    const float3 n = normalize(cross(tr.v1-tr.v0, tr.v2-tr.v0));

    const float3 dU = Uold - Unew;
    const float IU_ortI = dot(dU, n);
    const float3 U_par = dU - IU_ortI * n;

    const float a = M * IU_ortI;
    const float v0_ort = O_barycentric.x * a;
    const float v1_ort = O_barycentric.y * a;
    const float v2_ort = O_barycentric.z * a;

    const float3 C  = oneThrird * (tr.v0+tr.v1+tr.v2);
    const float3 Vc = oneThrird * M * U_par;

    const float3 O = O_barycentric.x * tr.v0 + O_barycentric.y * tr.v1 + O_barycentric.z * tr.v2;
    const float3 L = M * cross(C-O, U_par);

    const float J = len2(C-tr.v0) + len2(C-tr.v1) + len2(C-tr.v2);
    if (fabsf(J) < tol)
    {
        const float3 f = dU * M / dt;
        f0 = O_barycentric.x*f;
        f1 = O_barycentric.y*f;
        f2 = O_barycentric.z*f;

        return;
    }

    const float w = -dot(L, n) / J;

    const float3 orth_r0 = cross(C-tr.v0, n);
    const float3 orth_r1 = cross(C-tr.v1, n);
    const float3 orth_r2 = cross(C-tr.v2, n);

    const float3 u0 = w * orth_r0;
    const float3 u1 = w * orth_r1;
    const float3 u2 = w * orth_r2;

    const float3 v0 = v0_ort*n + Vc + u0;
    const float3 v1 = v1_ort*n + Vc + u1;
    const float3 v2 = v2_ort*n + Vc + u2;

    const float invdt = 1.0f / dt;
    f0 = v0 * invdt;
    f1 = v1 * invdt;
    f2 = v2 * invdt;
}


template <class BounceKernel>
__global__ void performBouncingTriangle(OVviewWithNewOldVertices objView,
                                        PVviewWithOldParticles pvView,
                                        MeshView mesh,
                                        int nCollisions, int2 *collisionTable, int *collisionTimes,
                                        const float dt,
                                        const BounceKernel bounceKernel)
{
    constexpr float eps = 5e-5f;

    const int gid = blockIdx.x * blockDim.x + threadIdx.x;
    if (gid >= nCollisions) return;

    const int2 pid_trid = collisionTable[gid];
    const int pid = pid_trid.x;

    const Particle p (pvView.readParticle   (pid));

    const auto rOld = pvView.readOldPosition(pid);
    const int trid  = pid_trid.y % mesh.ntriangles;
    const int objId = pid_trid.y / mesh.ntriangles;

    const int3 triangle = mesh.triangles[trid];
    const Triangle tr =    readTriangle(objView.vertices    , mesh.nvertices*objId, triangle);
    const Triangle trOld = readTriangle(objView.old_vertices, mesh.nvertices*objId, triangle);

    const auto info = intersectSegmentWithTriangle(tr, trOld, p.r, rOld);

    const int minTime = collisionTimes[pid];

    if (1.0f - info.alpha != __int_as_float(minTime)) return;

    const float3 barycentricCoo = barycentric(info.triangle, info.point);

    const float dt_1 = 1.0f / dt;
    const Triangle trVel = { (tr.v0-trOld.v0)*dt_1, (tr.v1-trOld.v1)*dt_1, (tr.v2-trOld.v2)*dt_1 };

    // Position is based on INTERMEDIATE barycentric collision coordinates and FINAL triangle
    const float3 vtri = barycentricCoo.x*trVel.v0 + barycentricCoo.y*trVel.v1 + barycentricCoo.z*trVel.v2;
    const float3 coo  = barycentricCoo.x*tr.v0    + barycentricCoo.y*tr.v1    + barycentricCoo.z*tr.v2;

    float3 n = normalize(cross(tr.v1-tr.v0, tr.v2-tr.v0));
    n = (info.sign > 0) ? n : -n;

    // new velocity relative to the triangle speed
    const float3 newV = bounceKernel.newVelocity(p.u, vtri, n, pvView.mass);

    float3 f0, f1, f2;
    triangleForces(tr, objView.mass, barycentricCoo, p.u, newV, pvView.mass, dt, f0, f1, f2);

    Particle corrP {p};
    corrP.r = coo + eps * n;
    corrP.u = newV;

    pvView.writeParticle(pid, corrP);

    atomicAdd(objView.vertexForces + mesh.nvertices*objId + triangle.x, f0);
    atomicAdd(objView.vertexForces + mesh.nvertices*objId + triangle.y, f1);
    atomicAdd(objView.vertexForces + mesh.nvertices*objId + triangle.z, f2);
}

} // namespace MeshBounceKernels
