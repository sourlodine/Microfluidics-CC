#include "membrane.h"

#include <core/pvs/membrane_vector.h>
#include <core/pvs/particle_vector.h>
#include <core/utils/quaternion.h>

#include <fstream>
#include <random>

MembraneIC::MembraneIC(PyTypes::VectorOfFloat7 com_q, float globalScale) :
    com_q(com_q), globalScale(globalScale)
{}

MembraneIC::~MembraneIC() = default;

/**
 * Read mesh topology and initial vertices (vertices are same as particles for RBCs)
 *
 * Then read the center of mass coordinates of the cells and their orientation
 * quaternions from file #icfname.
 *
 * The format of the initial conditions file is such that each line defines
 * one RBC with the following 7 numbers separated by spaces:
 * <tt>COM.x COM.y COM.z  Q.x Q.y Q.z Q.w</tt>
 * \sa quaternion.h
 *
 * To generate an RBC from the IC file, the initial coordinate pattern will be
 * shifted to the COM and rotated according to Q.
 *
 * The RBCs with COM outside of an MPI process's domain will be discarded on
 * that process.
 *
 * Set unique id to all the particles and also write unique cell ids into
 * 'ids' per-object channel
 */
void MembraneIC::exec(const MPI_Comm& comm, ParticleVector* pv, cudaStream_t stream)
{
    auto ov = dynamic_cast<MembraneVector*>(pv);
    auto domain = pv->state->domain;
    
    if (ov == nullptr)
        die("RBCs can only be generated out of rbc object vectors");

    // Local number of objects
    int nObjs=0;

    for (auto& entry : com_q)
    {
        float3 com = {entry[0], entry[1], entry[2]};
        float4 q   = {entry[3], entry[4], entry[5], entry[6]};

        q = normalize(q);

        if (domain.globalStart.x <= com.x && com.x < domain.globalStart.x + domain.localSize.x &&
            domain.globalStart.y <= com.y && com.y < domain.globalStart.y + domain.localSize.y &&
            domain.globalStart.z <= com.z && com.z < domain.globalStart.z + domain.localSize.z)
        {
            com = domain.global2local(com);
            int oldSize = ov->local()->size();
            ov->local()->resize(oldSize + ov->mesh->getNvertices(), stream);

            auto& pos = ov->local()->positions();
            auto& vel = ov->local()->velocities();
            
            for (int i=0; i<ov->mesh->getNvertices(); i++)
            {
                float3 r = rotate(f4tof3( ov->mesh->vertexCoordinates[i] * globalScale ), q) + com;
                Particle p;
                p.r = r;
                p.u = make_float3(0);

                pos[oldSize + i] = p.r2Float4();
                vel[oldSize + i] = p.u2Float4();
            }

            nObjs++;
        }
    }

    ov->local()->positions().uploadToDevice(stream);
    ov->local()->velocities().uploadToDevice(stream);
    ov->local()->computeGlobalIds(comm, stream);
    ov->local()->dataPerParticle.getData<float4>(ChannelNames::oldPositions)->copy(ov->local()->positions(), stream);

    info("Initialized %d '%s' membranes", nObjs, ov->name.c_str());
}

