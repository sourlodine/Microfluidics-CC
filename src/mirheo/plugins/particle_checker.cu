#include "particle_checker.h"
#include "utils/time_stamp.h"

#include <mirheo/core/datatypes.h>
#include <mirheo/core/pvs/particle_vector.h>
#include <mirheo/core/pvs/rigid_object_vector.h>
#include <mirheo/core/pvs/views/pv.h>
#include <mirheo/core/pvs/views/rov.h>
#include <mirheo/core/simulation.h>
#include <mirheo/core/types/str.h>
#include <mirheo/core/utils/cuda_common.h>
#include <mirheo/core/utils/kernel_launch.h>
#include <mirheo/core/utils/strprintf.h>

namespace mirheo
{

namespace ParticleCheckerKernels
{
template<typename R3>
__device__ static inline bool isFinite(R3 v)
{
    return isfinite(v.x) && isfinite(v.y) && isfinite(v.z);
}

template<typename R3>
__device__ static inline bool withinBounds(R3 v, real3 bounds)
{
    return
        (math::abs(v.x) < bounds.x) &&
        (math::abs(v.y) < bounds.y) &&
        (math::abs(v.z) < bounds.z);
}

__device__ static inline void setBadStatus(int pid, ParticleCheckerPlugin::Info info, ParticleCheckerPlugin::ParticleStatus *status)
{
    const auto tag = atomicExch(&status->tag, ParticleCheckerPlugin::BadTag);

    if (tag == ParticleCheckerPlugin::GoodTag)
    {
        status->id   = pid;
        status->info = info;
    }
}

__global__ void checkForces(PVview view, ParticleCheckerPlugin::ParticleStatus *status)
{
    const int pid = blockIdx.x * blockDim.x + threadIdx.x;

    if (pid >= view.size) return;

    const auto force = make_real3(view.forces[pid]);

    if (!isFinite(force))
        setBadStatus(pid, ParticleCheckerPlugin::Info::Nan, status);
}

__global__ void checkParticles(PVview view, DomainInfo domain, real dtInv, ParticleCheckerPlugin::ParticleStatus *status)
{
    const int pid = blockIdx.x * blockDim.x + threadIdx.x;

    if (pid >= view.size) return;

    const auto pos = make_real3(view.readPosition(pid));
    const auto vel = make_real3(view.readVelocity(pid));

    if (!isFinite(pos) || !isFinite(vel))
    {
        setBadStatus(pid, ParticleCheckerPlugin::Info::Nan, status);
        return;
    }

    const real3 boundsPos = 1.5_r * domain.localSize; // particle should not be further than one neighbouring domain
    const real3 boundsVel = dtInv * domain.localSize; // particle should not travel more than one domain size per iteration

    if (!withinBounds(pos, boundsPos) || !withinBounds(vel, boundsVel))
    {
        setBadStatus(pid, ParticleCheckerPlugin::Info::Out, status);
        return;
    }
}

__global__ void checkRigidForces(ROVview view, ParticleCheckerPlugin::ParticleStatus *status)
{
    const int objId = blockIdx.x * blockDim.x + threadIdx.x;

    if (objId >= view.nObjects) return;

    const auto m = view.motions[objId];

    if (!isFinite(m.force) || !isFinite(m.torque))
        setBadStatus(objId, ParticleCheckerPlugin::Info::Nan, status);
}

__global__ void checkRigidMotions(ROVview view, DomainInfo domain, real dtInv, ParticleCheckerPlugin::ParticleStatus *status)
{
    const int objId = blockIdx.x * blockDim.x + threadIdx.x;

    if (objId >= view.nObjects) return;

    const auto m = view.motions[objId];

    if (!isFinite(m.r) || !isFinite(m.vel) || !isFinite(m.omega))
    {
        setBadStatus(objId, ParticleCheckerPlugin::Info::Nan, status);
        return;
    }

    const real3 boundsPos   = 1.5_r * domain.localSize; // objects should not be further than one neighbouring domain
    const real3 boundsVel   = dtInv * domain.localSize; // objects should not travel more than one domain size per iteration
    const real3 boundsOmega = make_real3(dtInv * M_PI); // objects should not rotate more than half a turn per iteration

    if (!withinBounds(m.r, boundsPos) || !withinBounds(m.vel, boundsVel), !withinBounds(m.omega, boundsOmega))
    {
        setBadStatus(objId, ParticleCheckerPlugin::Info::Out, status);
        return;
    }
}

} // namespace ParticleCheckerKernels

constexpr int ParticleCheckerPlugin::NotRov_;

ParticleCheckerPlugin::ParticleCheckerPlugin(const MirState *state, std::string name, int checkEvery) :
    SimulationPlugin(state, name),
    checkEvery_(checkEvery)
{}

ParticleCheckerPlugin::~ParticleCheckerPlugin() = default;

void ParticleCheckerPlugin::setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm)
{
    SimulationPlugin::setup(simulation, comm, interComm);
    pvs_ = simulation->getParticleVectors();
    rovStatusIds_.clear();
    
    int numRovs {0};
    for (auto pv : pvs_)
    {
        int id = NotRov_;
        if (dynamic_cast<RigidObjectVector*>(pv))
        {
            id = pvs_.size() + numRovs++;
        }
        rovStatusIds_.push_back(id);
    }

    statuses_.resize_anew(pvs_.size() + numRovs);

    for (auto& s : statuses_)
        s = {GoodTag, 0, Info::Ok};
    statuses_.uploadToDevice(defaultStream);
}

void ParticleCheckerPlugin::beforeIntegration(cudaStream_t stream)
{
    if (!isTimeEvery(getState(), checkEvery_)) return;

    constexpr int nthreads = 128;
    
    for (size_t i = 0; i < pvs_.size(); ++i)
    {
        auto pv = pvs_[i];
        PVview view(pv, pv->local());

        SAFE_KERNEL_LAUNCH(
            ParticleCheckerKernels::checkForces,
            getNblocks(view.size, nthreads), nthreads, 0, stream,
            view, statuses_.devPtr() + i );

        if (auto rov = dynamic_cast<RigidObjectVector*>(pv))
        {
            ROVview view(rov, rov->local());

            SAFE_KERNEL_LAUNCH(
                ParticleCheckerKernels::checkRigidForces,
                getNblocks(view.nObjects, nthreads), nthreads, 0, stream,
                view, statuses_.devPtr() + rovStatusIds_[i] );
        }
    }

    dieIfBadStatus(stream, "force");
}

void ParticleCheckerPlugin::afterIntegration(cudaStream_t stream)
{
    if (!isTimeEvery(getState(), checkEvery_)) return;

    constexpr int nthreads = 128;

    const real dt     = getState()->dt;
    const real dtInv  = 1.0_r / math::max(1e-6_r, dt);
    const auto domain = getState()->domain;
    
    for (size_t i = 0; i < pvs_.size(); ++i)
    {
        auto pv = pvs_[i];
        PVview view(pv, pv->local());

        SAFE_KERNEL_LAUNCH(
            ParticleCheckerKernels::checkParticles,
            getNblocks(view.size, nthreads), nthreads, 0, stream,
            view, domain, dtInv, statuses_.devPtr() + i );

        if (auto rov = dynamic_cast<RigidObjectVector*>(pv))
        {
            ROVview view(rov, rov->local());

            SAFE_KERNEL_LAUNCH(
                ParticleCheckerKernels::checkRigidMotions,
                getNblocks(view.nObjects, nthreads), nthreads, 0, stream,
                view, domain, dtInv, statuses_.devPtr() + rovStatusIds_[i] );
        }
    }

    dieIfBadStatus(stream, "particle");
}

static inline void downloadAllFields(cudaStream_t stream, const DataManager& manager)
{
    for (auto entry : manager.getSortedChannels())
    {
        auto desc = entry.second;
        mpark::visit([stream](auto pinnedBuffPtr)
        {
            pinnedBuffPtr->downloadFromDevice(stream, ContainersSynch::Asynch);
        }, desc->varDataPtr);
    }
    CUDA_Check( cudaStreamSynchronize(stream) );
}

static inline std::string listOtherFieldValues(const DataManager& manager, int id)
{
    std::string fieldValues;
    
    for (auto entry : manager.getSortedChannels())
    {
        const auto& name = entry.first;
        const auto desc = entry.second;
            
        if (name == ChannelNames::positions ||
            name == ChannelNames::velocities)
            continue;
            
        mpark::visit([&](auto pinnedBuffPtr)
        {
            const auto val = (*pinnedBuffPtr)[id];
            fieldValues += '\t' + name + " : " + printToStr(val) + '\n';
        }, desc->varDataPtr);
    }
    return fieldValues;    
}

static inline std::string infoToStr(ParticleCheckerPlugin::Info info)
{
    using Info = ParticleCheckerPlugin::Info;
    if (info == Info::Nan) return "not a finite number";
    if (info == Info::Out) return "out of bounds";
    return "no error detected";
}

void ParticleCheckerPlugin::dieIfBadStatus(cudaStream_t stream, const std::string& identifier)
{
    statuses_.downloadFromDevice(stream, ContainersSynch::Synch);
    const auto domain = getState()->domain;

    bool failing {false};
    std::string allErrors;

    for (size_t i = 0; i < pvs_.size(); ++i)
    {
        const auto& partStatus = statuses_[i];
        if (partStatus.tag == GoodTag) continue;

        const int partId = partStatus.id;

        // from now we know we will fail; download particles and print error
        auto pv = pvs_[i];
        auto lpv = pv->local();

        downloadAllFields(stream, lpv->dataPerParticle);

        const auto p = Particle(lpv->positions ()[partId],
                                lpv->velocities()[partId]);

        const auto infoStr = infoToStr(partStatus.info);

        const real3 lr = p.r;
        const real3 gr = domain.local2global(lr);

        allErrors += strprintf("\n\tBad %s in '%s' with id %ld, local position %g %g %g, global position %g %g %g, velocity %g %g %g : %s\n",
                               identifier.c_str(),
                               pv->getCName(), p.getId(),
                               lr.x, lr.y, lr.z, gr.x, gr.y, gr.z,
                               p.u.x, p.u.y, p.u.z, infoStr.c_str());

        allErrors += listOtherFieldValues(lpv->dataPerParticle, partId);
        
        failing = true;
    }

    for (size_t i = 0; i < pvs_.size(); ++i)
    {
        const int rovSId = rovStatusIds_[i];
        if (rovSId == NotRov_) continue;
        
        const auto& rovStatus = statuses_[rovSId];
        if (rovStatus.tag == GoodTag) continue;

        const int rovId = rovStatus.id;

        // from now we know we will fail; download particles and print error
        auto rov = dynamic_cast<RigidObjectVector*>(pvs_[i]);
        auto lrov = rov->local();

        downloadAllFields(stream, lrov->dataPerObject);

        const auto infoStr = infoToStr(rovStatus.info);
        
        allErrors += strprintf("\n\tBad %s in rov '%s' : %s\n",
                               identifier.c_str(), rov->getCName(), infoStr.c_str());

        allErrors += listOtherFieldValues(lrov->dataPerObject, rovId);
        
        failing = true;
    }

    if (failing)
        die("Particle checker has found bad particles: %s", allErrors.c_str());
}

} // namespace mirheo
