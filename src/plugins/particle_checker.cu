#include "particle_checker.h"
#include "utils/time_stamp.h"

#include <core/datatypes.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/views/pv.h>
#include <core/simulation.h>
#include <core/utils/cuda_common.h>
#include <core/utils/kernel_launch.h>

namespace ParticleCheckerKernels
{
__device__ inline bool checkFinite(float3 v)
{
    return isfinite(v.x) && isfinite(v.y) && isfinite(v.z);
}

__device__ inline bool withinBounds(float3 v, float3 bounds)
{
    return
        (fabs(v.x) < bounds.x) &&
        (fabs(v.y) < bounds.y) &&
        (fabs(v.z) < bounds.z);
}

__global__ void checkParticles(PVview view, DomainInfo domain, float dtInv, ParticleCheckerPlugin::ParticleStatus *status)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;

    if (pid >= view.size) return;

    auto pos = make_float3(view.readPosition(pid));
    auto vel = make_float3(view.readVelocity(pid));

    if (!checkFinite(pos) || !checkFinite(vel))
    {
        *status = {ParticleCheckerPlugin::Status::Nan, pid};
        return; // TODO: atomics?
    }

    float3 boundsPos = 1.5f  * domain.localSize; // particle should not be further that in a neighbouring domain
    float3 boundsVel = dtInv * domain.localSize; // particle should not travel more than one domain size per iteration

    if (!withinBounds(pos, boundsPos) || !withinBounds(vel, boundsVel))
    {
        *status = {ParticleCheckerPlugin::Status::Out, pid};
        return;
    }
}
} // namespace ParticleCheckerKernels
    
ParticleCheckerPlugin::ParticleCheckerPlugin(const YmrState *state, std::string name, int checkEvery) :
    SimulationPlugin(state, name),
    checkEvery(checkEvery)
{}

ParticleCheckerPlugin::~ParticleCheckerPlugin() = default;

void ParticleCheckerPlugin::setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm)
{
    SimulationPlugin::setup(simulation, comm, interComm);
    pvs = simulation->getParticleVectors();

    statuses.resize_anew(pvs.size());

    for (auto& s : statuses)
        s = {Status::Ok, 0};
    statuses.uploadToDevice(defaultStream);
}

void ParticleCheckerPlugin::afterIntegration(cudaStream_t stream)
{
    if (!isTimeEvery(state, checkEvery)) return;

    const int nthreads = 128;

    auto dtInv = 1.0f / state->dt;
    auto domain = state->domain;
    
    for (size_t i = 0; i < pvs.size(); ++i)
    {
        auto pv = pvs[i];
        PVview view(pv, pv->local());

        SAFE_KERNEL_LAUNCH(
            ParticleCheckerKernels::checkParticles,
            getNblocks(view.size, nthreads), nthreads, 0, stream,
            view, domain, dtInv, statuses.devPtr() + i );
    }

    statuses.downloadFromDevice(stream, ContainersSynch::Synch);

    for (size_t i = 0; i < pvs.size(); ++i)
    {
        const auto& s = statuses[i];
        if (s.status == Status::Ok) continue;

        // from now we know we will fail; download particles and print error
        auto pv = pvs[i];
        auto lpv = pv->local();
        lpv->positions ().downloadFromDevice(stream, ContainersSynch::Asynch);
        lpv->velocities().downloadFromDevice(stream, ContainersSynch::Synch);

        auto p = Particle(lpv->positions ()[s.id],
                          lpv->velocities()[s.id]);

        die("Bad particle with id %ld, position %g %g %g, velocity %g %g %g : %s",
            p.getId(), p.r.x, p.r.y, p.r.z, p.u.x, p.u.y, p.u.z,
            s.status == Status::Nan ? "non finite number" : "out of bounds");
    }
}

