#include "object_belonging.h"

#include <core/utils/kernel_launch.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/views/pv.h>
#include <core/pvs/object_vector.h>

#include <core/celllist.h>

__global__ void copyInOut(PVview view, const BelongingTags *tags,
                          float4 *insPos, float4 *insVel,
                          float4 *outPos, float4 *outVel,
                          int *nIn, int *nOut)
{
    const int gid = blockIdx.x * blockDim.x + threadIdx.x;
    if (gid >= view.size) return;

    auto tag = tags[gid];
    const Particle p(view.readParticle(gid));

    if (tag == BelongingTags::Outside)
    {
        int dstId = atomicAggInc(nOut);
        if (outPos) outPos[dstId] = p.r2Float4();
        if (outVel) outVel[dstId] = p.u2Float4();
    }

    if (tag == BelongingTags::Inside)
    {
        int dstId = atomicAggInc(nIn);
        if (insPos) insPos[dstId] = p.r2Float4();
        if (insVel) insVel[dstId] = p.u2Float4();
    }
}

ObjectBelongingChecker_Common::ObjectBelongingChecker_Common(const YmrState *state, std::string name) :
    ObjectBelongingChecker(state, name)
{}

ObjectBelongingChecker_Common::~ObjectBelongingChecker_Common() = default;


static void copyToLpv(int start, int n, const float4 *pos, const float4 *vel, LocalParticleVector *lpv, cudaStream_t stream)
{
    if (n <= 0) return;

    CUDA_Check( cudaMemcpyAsync(lpv->positions().devPtr() + start,
                                pos, n * sizeof(pos[0]), 
                                cudaMemcpyDeviceToDevice, stream) );

    CUDA_Check( cudaMemcpyAsync(lpv->velocities().devPtr() + start,
                                vel, n * sizeof(vel[0]),
                                cudaMemcpyDeviceToDevice, stream) );
}

void ObjectBelongingChecker_Common::splitByBelonging(ParticleVector* src, ParticleVector* pvIn, ParticleVector* pvOut, cudaStream_t stream)
{
    if (dynamic_cast<ObjectVector*>(src) != nullptr)
        error("Trying to split object vector %s into two per-particle, probably that's not what you wanted",
              src->name.c_str());

    if (pvIn != nullptr && typeid(*src) != typeid(*pvIn))
        error("PV type of inner result of split (%s) is different from source (%s)",
              pvIn->name.c_str(), src->name.c_str());

    if (pvOut != nullptr && typeid(*src) != typeid(*pvOut))
        error("PV type of outer result of split (%s) is different from source (%s)",
              pvOut->name.c_str(), src->name.c_str());

    {
        PrimaryCellList cl(src, 1.0f, state->domain.localSize);
        cl.build(stream);
        checkInner(src, &cl, stream);
    }

    info("Splitting PV %s with respect to OV %s. Number of particles: in/out/total %d / %d / %d",
         src->name.c_str(), ov->name.c_str(), nInside[0], nOutside[0], src->local()->size());

    // Need buffers because the source is the same as inside or outside
    PinnedBuffer<float4> bufInsPos(nInside[0] ), bufInsVel(nInside[0] );
    PinnedBuffer<float4> bufOutPos(nOutside[0]), bufOutVel(nOutside[0]);

    nInside. clearDevice(stream);
    nOutside.clearDevice(stream);
    tags.downloadFromDevice(stream);

    PVview view(src, src->local());
    const int nthreads = 128;
    SAFE_KERNEL_LAUNCH(
            copyInOut,
            getNblocks(view.size, nthreads), nthreads, 0, stream,
            view, tags.devPtr(),
            bufInsPos.devPtr(), bufInsVel.devPtr(),
            bufOutPos.devPtr(), bufOutVel.devPtr(),
            nInside.devPtr(), nOutside.devPtr() );

    CUDA_Check( cudaStreamSynchronize(stream) );

    if (pvIn  != nullptr)
    {
        int oldSize = (src == pvIn) ? 0 : pvIn->local()->size();
        pvIn->local()->resize(oldSize + nInside[0], stream);

        copyToLpv(oldSize, nInside[0], bufInsPos.devPtr(), bufInsVel.devPtr(), pvIn->local(), stream);

        info("New size of inner PV %s is %d", pvIn->name.c_str(), pvIn->local()->size());
        pvIn->cellListStamp++;
    }

    if (pvOut != nullptr)
    {
        int oldSize = (src == pvOut) ? 0 : pvOut->local()->size();
        pvOut->local()->resize(oldSize + nOutside[0], stream);

        copyToLpv(oldSize, nOutside[0], bufOutPos.devPtr(), bufOutVel.devPtr(), pvOut->local(), stream);

        info("New size of outer PV %s is %d", pvOut->name.c_str(), pvOut->local()->size());
        pvOut->cellListStamp++;
    }
}

void ObjectBelongingChecker_Common::checkInner(ParticleVector* pv, CellList* cl, cudaStream_t stream)
{
    tagInner(pv, cl, stream);

    nInside.clear(stream);
    nOutside.clear(stream);

    // Only count
    PVview view(pv, pv->local());
    const int nthreads = 128;
    SAFE_KERNEL_LAUNCH(
                copyInOut,
                getNblocks(view.size, nthreads), nthreads, 0, stream,
                view, tags.devPtr(), nullptr, nullptr, nullptr, nullptr,
                nInside.devPtr(), nOutside.devPtr() );

    nInside. downloadFromDevice(stream, ContainersSynch::Asynch);
    nOutside.downloadFromDevice(stream, ContainersSynch::Synch);

    say("PV %s belonging check against OV %s: in/out/total  %d / %d / %d",
        pv->name.c_str(), ov->name.c_str(), nInside[0], nOutside[0], pv->local()->size());
}

void ObjectBelongingChecker_Common::setup(ObjectVector* ov)
{
    this->ov = ov;
}

std::vector<std::string> ObjectBelongingChecker_Common::getChannelsToBeExchanged() const
{
    return {ChannelNames::motions};
}

ObjectVector* ObjectBelongingChecker_Common::getObjectVector()
{
    return ov;
}
