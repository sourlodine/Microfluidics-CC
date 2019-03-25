#pragma once

#include <core/bounce_solver.h>
#include <core/celllist.h>
#include <core/pvs/rigid_object_vector.h>
#include <core/pvs/views/reov.h>
#include <core/utils/cuda_common.h>
#include <core/utils/quaternion.h>

__device__ inline float ellipsoidF(const float3 r, const float3 invAxes)
{
    return sqr(r.x * invAxes.x) + sqr(r.y * invAxes.y) + sqr(r.z * invAxes.z) - 1.0f;
}

__device__ inline void bounceCellArray(
        REOVviewWithOldMotion ovView, PVviewWithOldParticles pvView,
        int objId,
        int* validCells, int nCells,
        CellListInfo cinfo, const float dt)
{
    const float threshold = 2e-5f;

    auto motion     = toSingleMotion( ovView.motions[objId] );
    auto old_motion = toSingleMotion( ovView.old_motions[objId] );

    const float3 axes    = ovView.axes;
    const float3 invAxes = ovView.invAxes;

    if (threadIdx.x >= nCells) return;

    int cid = validCells[threadIdx.x];
    int pstart = cinfo.cellStarts[cid];
    int pend   = cinfo.cellStarts[cid+1];

    // XXX: changing reading layout may improve performance here
    for (int pid = pstart; pid < pend; pid++)
    {
        Particle p    (pvView.particles,     pid);
        Particle old_p(pvView.old_particles, pid);

        // Go to the obj frame of reference
        float3 coo    = rotate(p.r     - motion.r,     invQ(motion.q));
        float3 oldCoo = rotate(old_p.r - old_motion.r, invQ(old_motion.q));
        float3 dr = coo - oldCoo;

        // If the particle is outside - skip it, it's fine
        if (ellipsoidF(coo, invAxes) > 0.0f) continue;

        // This is intersection point
        float alpha = solveLinSearch( [=] (const float lambda) { return ellipsoidF(oldCoo + dr*lambda, invAxes);} );
        float3 newCoo = oldCoo + dr*max(alpha, 0.0f);

        // Push out a little bit
        float3 normal = normalize(make_float3(
                axes.y*axes.y * axes.z*axes.z * newCoo.x,
                axes.z*axes.z * axes.x*axes.x * newCoo.y,
                axes.x*axes.x * axes.y*axes.y * newCoo.z));

        newCoo += threshold*normal;

        // If smth went notoriously bad
        if (ellipsoidF(newCoo, invAxes) < 0.0f)
        {
            printf("Bounce-back failed on particle %d (%f %f %f)  %f -> %f to %f, alpha %f. Recovering to old position\n",
                    p.i1, p.r.x, p.r.y, p.r.z,
                    ellipsoidF(oldCoo, invAxes), ellipsoidF(coo, invAxes),
                    ellipsoidF(newCoo - threshold*normal, invAxes), alpha);

            newCoo = oldCoo;
        }

        // Return to the original frame
        newCoo = rotate(newCoo, motion.q) + motion.r;

        // Change velocity's frame to the object frame, correct for rotation as well
        float3 vEll = motion.vel + cross( motion.omega, newCoo-motion.r );
        float3 newU = vEll - (p.u - vEll);

        const float3 frc = -pvView.mass * (newU - p.u) / dt;
        atomicAdd( &ovView.motions[objId].force,  make_rigidReal3(frc));
        atomicAdd( &ovView.motions[objId].torque, make_rigidReal3(cross(newCoo - motion.r, frc)) );

        p.r = newCoo;
        p.u = newU;
        p.write2Float4(pvView.particles, pid);
    }
}

__device__ inline bool isValidCell(int3 cid3, SingleRigidMotion motion, CellListInfo cinfo, float3 invAxes)
{
    const float threshold = 0.5f;

    float3 v000 = make_float3(cid3) * cinfo.h - cinfo.localDomainSize*0.5f - motion.r;
    const float4 invq = invQ(motion.q);

    float3 v001 = rotate( v000 + make_float3(        0,         0, cinfo.h.z), invq );
    float3 v010 = rotate( v000 + make_float3(        0, cinfo.h.y,         0), invq );
    float3 v011 = rotate( v000 + make_float3(        0, cinfo.h.y, cinfo.h.z), invq );
    float3 v100 = rotate( v000 + make_float3(cinfo.h.x,         0,         0), invq );
    float3 v101 = rotate( v000 + make_float3(cinfo.h.x,         0, cinfo.h.z), invq );
    float3 v110 = rotate( v000 + make_float3(cinfo.h.x, cinfo.h.y,         0), invq );
    float3 v111 = rotate( v000 + make_float3(cinfo.h.x, cinfo.h.y, cinfo.h.z), invq );

    v000 = rotate( v000, invq );

    return ( ellipsoidF(v000, invAxes) < threshold ||
             ellipsoidF(v001, invAxes) < threshold ||
             ellipsoidF(v010, invAxes) < threshold ||
             ellipsoidF(v011, invAxes) < threshold ||
             ellipsoidF(v100, invAxes) < threshold ||
             ellipsoidF(v101, invAxes) < threshold ||
             ellipsoidF(v110, invAxes) < threshold ||
             ellipsoidF(v111, invAxes) < threshold );
}

__global__ void bounceEllipsoid(REOVviewWithOldMotion ovView, PVviewWithOldParticles pvView,
        CellListInfo cinfo, const float dt)
{
    // About max travel distance per step + safety
    // Safety comes from the fact that bounce works with the analytical shape,
    //  and extent is computed w.r.t. particles
    const int tol = 1.5f;

    const int objId = blockIdx.x;
    const int tid = threadIdx.x;
    if (objId >= ovView.nObjects) return;

    // Preparation step. Filter out all the cells that don't intersect the surface
    __shared__ volatile int nCells;
    extern __shared__ int validCells[];

    nCells = 0;
    __syncthreads();

    const int3 cidLow  = cinfo.getCellIdAlongAxes(ovView.comAndExtents[objId].low  - tol);
    const int3 cidHigh = cinfo.getCellIdAlongAxes(ovView.comAndExtents[objId].high + tol);

    const int3 span = cidHigh - cidLow + make_int3(1,1,1);
    const int totCells = span.x * span.y * span.z;

//    if (  ovView.motions[objId].r.x < -15.9 )
//    {
//        auto motion = ovView.motions[objId];
//        if(threadIdx.x == 0)
//        printf("obj  %d  r [%f %f %f]   v [%f %f %f],  f [%f %f %f],  t [%f %f %f],   \n"
//                "    q [%f %f %f %f]   w [%f %f %f] \n", ovView.ids[objId],
//                motion.r.x,  motion.r.y,  motion.r.z,
//                motion.vel.x,  motion.vel.y,  motion.vel.z,
//                motion.force.x,  motion.force.y,  motion.force.z,
//                motion.torque.x, motion.torque.y, motion.torque.z ,
//                motion.q.x,  motion.q.y,  motion.q.z, motion.q.w,
//                motion.omega.x,  motion.omega.y,  motion.omega.z);
//
//        motion = ovView.old_motions[objId];
//        if(threadIdx.x == 0)
//        printf("OLD obj  %d  r [%f %f %f]   v [%f %f %f],  f [%f %f %f],  t [%f %f %f],   \n"
//                "    q [%f %f %f %f]   w [%f %f %f] \n", ovView.ids[objId],
//                motion.r.x,  motion.r.y,  motion.r.z,
//                motion.vel.x,  motion.vel.y,  motion.vel.z,
//                motion.force.x,  motion.force.y,  motion.force.z,
//                motion.torque.x, motion.torque.y, motion.torque.z ,
//                motion.q.x,  motion.q.y,  motion.q.z, motion.q.w,
//                motion.omega.x,  motion.omega.y,  motion.omega.z);
//    }

    for (int i=tid; i-tid < totCells; i+=blockDim.x)
    {
        const int3 cid3 = make_int3( i % span.x, (i/span.x) % span.y, i / (span.x*span.y) ) + cidLow;
        const int cid = cinfo.encode(cid3);

        if ( i < totCells &&
             cid < cinfo.totcells &&
             isValidCell(cid3, toSingleMotion(ovView.motions[objId]), cinfo, ovView.invAxes) )
        {
            int id = atomicAggInc((int*)&nCells);
            validCells[id] = cid;
        }

        __syncthreads();

        // If we have enough cells ready - process them
        if (nCells >= blockDim.x)
        {
            bounceCellArray(ovView, pvView, objId, validCells, blockDim.x, cinfo, dt);

            __syncthreads();

            if (tid == 0) nCells -= blockDim.x;
            validCells[tid] = validCells[tid + blockDim.x];

            __syncthreads();
        }
    }

    __syncthreads();

    // Process remaining
    bounceCellArray(ovView, pvView, objId, validCells, nCells, cinfo, dt);
}



