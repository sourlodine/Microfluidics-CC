#include "particle_checker.h"
#include "utils/time_stamp.h"

#include <mirheo/core/datatypes.h>
#include <mirheo/core/pvs/particle_vector.h>
#include <mirheo/core/pvs/views/pv.h>
#include <mirheo/core/simulation.h>
#include <mirheo/core/types/str.h>
#include <mirheo/core/utils/cuda_common.h>
#include <mirheo/core/utils/kernel_launch.h>
#include <mirheo/core/utils/strprintf.h>

namespace mirheo
{

namespace ParticleCheckerKernels
{
__device__ inline bool checkFinite(real3 v)
{
    return isfinite(v.x) && isfinite(v.y) && isfinite(v.z);
}

__device__ inline bool withinBounds(real3 v, real3 bounds)
{
    return
        (math::abs(v.x) < bounds.x) &&
        (math::abs(v.y) < bounds.y) &&
        (math::abs(v.z) < bounds.z);
}

__global__ void checkParticles(PVview view, DomainInfo domain, real dtInv, ParticleCheckerPlugin::ParticleStatus *status)
{
    const int pid = blockIdx.x * blockDim.x + threadIdx.x;

    if (pid >= view.size) return;

    const auto pos = make_real3(view.readPosition(pid));
    const auto vel = make_real3(view.readVelocity(pid));

    if (!checkFinite(pos) || !checkFinite(vel))
    {
        const auto tag = atomicExch(&status->tag, ParticleCheckerPlugin::BadTag);

        if (tag == ParticleCheckerPlugin::GoodTag)
        {
            status->id   = pid;
            status->info = ParticleCheckerPlugin::Info::Nan;
        }
        return;
    }

    const real3 boundsPos = 1.5_r  * domain.localSize; // particle should not be further than one neighbouring domain
    const real3 boundsVel = dtInv * domain.localSize; // particle should not travel more than one domain size per iteration

    if (!withinBounds(pos, boundsPos) || !withinBounds(vel, boundsVel))
    {
        const auto tag = atomicExch(&status->tag, ParticleCheckerPlugin::BadTag);

        if (tag == ParticleCheckerPlugin::GoodTag)
        {
            status->id   = pid;
            status->info = ParticleCheckerPlugin::Info::Out;
        }
        return;
    }
}
} // namespace ParticleCheckerKernels
    
ParticleCheckerPlugin::ParticleCheckerPlugin(const MirState *state, std::string name, int checkEvery) :
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
        s = {GoodTag, 0, Info::Ok};
    statuses.uploadToDevice(defaultStream);
}

void ParticleCheckerPlugin::afterIntegration(cudaStream_t stream)
{
    if (!isTimeEvery(getState(), checkEvery)) return;

    const int nthreads = 128;

    const real dt     = getState()->dt;
    const real dtInv  = 1.0_r / math::max(1e-6_r, dt);
    const auto domain = getState()->domain;
    
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

    bool failing {false};
    bool pvDownloaded {false};
    std::string allParticleErrors;

    for (size_t i = 0; i < pvs.size(); ++i, pvDownloaded = false)
    {
        const auto& s = statuses[i];
        if (s.tag == GoodTag) continue;

        // from now we know we will fail; download particles and print error
        auto pv = pvs[i];
        auto lpv = pv->local();

        if (!pvDownloaded)
        {
            for (auto entry : lpv->dataPerParticle.getSortedChannels())
            {
                auto desc = entry.second;
                mpark::visit([stream](auto pinnedBuffPtr)
                {
                    pinnedBuffPtr->downloadFromDevice(stream, ContainersSynch::Asynch);
                }, desc->varDataPtr);
            }
            CUDA_Check( cudaStreamSynchronize(stream) );
            pvDownloaded = true;
        }

        const auto p = Particle(lpv->positions ()[s.id],
                                lpv->velocities()[s.id]);

        const char *infoStr = s.info == Info::Nan ? "not a finite number" : "out of bounds";

        const real3 lr = p.r;
        const real3 gr = domain.local2global(lr);

        allParticleErrors += strprintf("\n\tBad particle in '%s' with id %ld, local position %g %g %g, global position %g %g %g, velocity %g %g %g : %s\n",
                                       pv->name.c_str(), p.getId(),
                                       lr.x, lr.y, lr.z, gr.x, gr.y, gr.z,
                                       p.u.x, p.u.y, p.u.z, infoStr);

        for (auto entry : lpv->dataPerParticle.getSortedChannels())
        {
            const auto& name = entry.first;
            const auto desc = entry.second;
            
            if (name == ChannelNames::positions ||
                name == ChannelNames::velocities)
                continue;
            
            mpark::visit([&](auto pinnedBuffPtr)
            {
                const auto val = (*pinnedBuffPtr)[s.id];
                allParticleErrors += '\t' + name + " : " + printToStr(val) + '\n';
            }, desc->varDataPtr);
        }
        
        failing = true;
    }

    if (failing)
        die("Particle checker has found bad particles: %s", allParticleErrors.c_str());
}

} // namespace mirheo
