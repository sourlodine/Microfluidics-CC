#pragma once

#include <core/utils/cuda_common.h>
#include <core/datatypes.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/views/pv.h>


/**
 * \code transform(Particle& p, const float3 f, const float invm, const float dt) \endcode
 *  is a callable that performs integration. It is called for
 *  every particle and should change velocity and coordinate
 *  of the Particle according to the chosen integration scheme.
 *
 * Will read from \c old_particles channel and write to ParticleVector::coosvels
 */
template<typename Transform>
__global__ void integrationKernel(PVviewWithOldParticles pvView, const float dt, Transform transform)
{
    const int gid = blockIdx.x * blockDim.x + threadIdx.x;
    const int pid = gid / 2;
    const int sh  = gid % 2;  // sh = 0 loads coordinate, sh = 1 -- velocity
    if (pid >= pvView.size) return;

    float4 val = readNoCache(pvView.old_particles + gid);
    Float3_int frc(pvView.forces[pid]);

    // Exchange coordinate and velocity with adjacent thread
    Particle p;
    float4 othval;
    int neighId = (sh == 0) ? threadIdx.x + 1 : threadIdx.x - 1;
    
    othval.x = __shfl(val.x, neighId);
    othval.y = __shfl(val.y, neighId);
    othval.z = __shfl(val.z, neighId);
    othval.w = __shfl(val.w, neighId);

    // val is coordinate, othval is corresponding velocity
    if (sh == 0)
    {
        p = Particle(val, othval);
        transform(p, frc.v, pvView.invMass, dt);
        val = p.r2Float4();
    }

    // val is velocity, othval is coordinate
    if (sh == 1)
    {
        p = Particle(othval, val);
        transform(p, frc.v, pvView.invMass, dt);
        val = p.u2Float4();
    }

    writeNoCache(pvView.particles + gid, val);
}
