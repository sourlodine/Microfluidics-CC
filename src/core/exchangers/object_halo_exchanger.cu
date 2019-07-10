#include "object_halo_exchanger.h"

#include "exchange_helpers.h"
#include "utils/common.h"
#include "utils/fragments_mapping.h"

#include <core/utils/kernel_launch.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/packers/objects.h>
#include <core/pvs/views/ov.h>
#include <core/logger.h>
#include <core/utils/cuda_common.h>

enum class PackMode
{
    Query, Pack
};

namespace ObjectHaloExchangeKernels
{

template <PackMode packMode, class PackerHandler>
__global__ void getObjectHaloAndMap(DomainInfo domain, OVview view, MapEntry *map,
                                    float rc, PackerHandler packer,
                                    BufferOffsetsSizesWrap dataWrap)
{
    const int objId = blockIdx.x;
    const int tid   = threadIdx.x;
    
    int nHalos = 0;
    short validHalos[7];

    if (objId < view.nObjects)
    {
        // Find to which halos this object should go
        auto prop = view.comAndExtents[objId];
        int dx = 0, dy = 0, dz = 0;

        if (prop.low.x  < -0.5f*domain.localSize.x + rc) dx = -1;
        if (prop.low.y  < -0.5f*domain.localSize.y + rc) dy = -1;
        if (prop.low.z  < -0.5f*domain.localSize.z + rc) dz = -1;

        if (prop.high.x >  0.5f*domain.localSize.x - rc) dx = 1;
        if (prop.high.y >  0.5f*domain.localSize.y - rc) dy = 1;
        if (prop.high.z >  0.5f*domain.localSize.z - rc) dz = 1;

        for (int ix = min(dx, 0); ix <= max(dx, 0); ++ix)
            for (int iy = min(dy, 0); iy <= max(dy, 0); ++iy)
                for (int iz = min(dz, 0); iz <= max(dz, 0); ++iz)
                {
                    if (ix == 0 && iy == 0 && iz == 0) continue;
                    const int bufId = FragmentMapping::getId(ix, iy, iz);
                    validHalos[nHalos] = bufId;
                    nHalos++;
                }
    }


    // Copy objects to each halo
    __shared__ int shDstObjId;

    for (int i = 0; i < nHalos; ++i)
    {
        const int bufId = validHalos[i];

        __syncthreads();
        if (tid == 0)
            shDstObjId = atomicAdd(dataWrap.sizes + bufId, 1);

        if (packMode == PackMode::Query)
        {
            continue;
        }
        else
        {
            __syncthreads();

            const int3 dir = FragmentMapping::getDir(bufId);
            auto shift = ExchangersCommon::getShift(domain.localSize, dir);

            auto buffer = dataWrap.getBuffer(bufId);
            int numElements = dataWrap.offsets[bufId+1] - dataWrap.offsets[bufId];

            packer.blockPackShift(numElements, buffer, objId, shDstObjId, shift);
            
            // save map
            
            int myOffset = dataWrap.offsets[bufId] + shDstObjId;
            if (tid == 0)
                map[myOffset] = MapEntry(objId, bufId);
        }
    }
}

template <class PackerHandler>
__global__ void unpackObjects(BufferOffsetsSizesWrap dataWrap, PackerHandler packer)
{
    const int objId = blockIdx.x;
    const int tid   = threadIdx.x;
    
    extern __shared__ int offsets[];
    
    const int nBuffers = dataWrap.nBuffers;

    for (int i = tid; i < nBuffers + 1; i += blockDim.x)
        offsets[i] = dataWrap.offsets[i];
    __syncthreads();

    const int bufId = dispatchThreadsPerBuffer(nBuffers, offsets, objId);
    auto buffer = dataWrap.getBuffer(bufId);
    const int numElements = dataWrap.sizes[bufId];
    
    const int srcObjId = objId - offsets[bufId];
    const int dstObjId = objId;

    packer.blockUnpack(numElements, buffer, srcObjId, dstObjId);
}

} // namespace ObjectHaloExchangeKernels


bool ObjectHaloExchanger::needExchange(int id)
{
    return !objects[id]->haloValid;
}

ObjectHaloExchanger::ObjectHaloExchanger() = default;
ObjectHaloExchanger::~ObjectHaloExchanger() = default;

void ObjectHaloExchanger::attach(ObjectVector *ov, float rc, const std::vector<std::string>& extraChannelNames)
{
    int id = objects.size();
    objects.push_back(ov);
    rcs.push_back(rc);

    auto channels = extraChannelNames;
    channels.push_back(ChannelNames::positions);
    channels.push_back(ChannelNames::velocities);

    PackPredicate predicate = [channels](const DataManager::NamedChannelDesc& namedDesc)
    {
        return std::find(channels.begin(), channels.end(), namedDesc.first) != channels.end();
    };
    
    auto   packer = std::make_unique<ObjectPacker>(predicate);
    auto unpacker = std::make_unique<ObjectPacker>(predicate);
    auto   helper = std::make_unique<ExchangeHelper>(ov->name, id, packer.get());

    packers  .push_back(std::move(  packer));
    unpackers.push_back(std::move(unpacker));
    helpers  .push_back(std::move(  helper));
    maps     .emplace_back();
    
    info("Object vector %s (rc %f) was attached to halo exchanger", ov->name.c_str(), rc);
}

void ObjectHaloExchanger::prepareSizes(int id, cudaStream_t stream)
{
    auto ov  = objects[id];
    auto lov = ov->local();
    auto rc  = rcs[id];
    auto helper = helpers[id].get();
    auto packer = packers[id].get();

    ov->findExtentAndCOM(stream, ParticleVectorType::Local);

    debug2("Counting halo objects of '%s'", ov->name.c_str());

    OVview ovView(ov, lov);
    helper->send.sizes.clear(stream);
    packer->update(lov, stream);

    if (ovView.nObjects > 0)
    {
        const int nthreads = 256;

        mpark::visit([&](auto packerHandler)
        {
            SAFE_KERNEL_LAUNCH(
                ObjectHaloExchangeKernels::getObjectHaloAndMap<PackMode::Query>,
                ovView.nObjects, nthreads, 0, stream,
                ov->state->domain, ovView, nullptr, rc,
                packerHandler, helper->wrapSendData() );
        }, ExchangersCommon::getHandler(packer));
    }

    helper->computeSendOffsets_Dev2Dev(stream);
}

void ObjectHaloExchanger::prepareData(int id, cudaStream_t stream)
{
    auto ov  = objects[id];
    auto lov = ov->local();
    auto rc  = rcs[id];
    auto helper = helpers[id].get();
    auto packer = packers[id].get();
    auto& map = maps[id];
    
    int nhalo = helper->send.offsets[helper->nBuffers];
    OVview ovView(ov, lov);
    map.resize_anew(nhalo);

    if (ovView.nObjects > 0)
    {
        const int nthreads = 256;
        debug2("Downloading %d halo objects of '%s'", nhalo, ov->name.c_str());

        helper->resizeSendBuf();
        helper->send.sizes.clearDevice(stream);
        
        mpark::visit([&](auto packerHandler)
        {
            SAFE_KERNEL_LAUNCH(
                ObjectHaloExchangeKernels::getObjectHaloAndMap<PackMode::Pack>,
                ovView.nObjects, nthreads, 0, stream,
                ov->state->domain, ovView, map.devPtr(), rc,
                packerHandler, helper->wrapSendData());
        }, ExchangersCommon::getHandler(packer));
    }
}

void ObjectHaloExchanger::combineAndUploadData(int id, cudaStream_t stream)
{
    auto ov       = objects[id];
    auto hov      = ov->halo();
    auto helper   = helpers[id].get();
    auto unpacker = unpackers[id].get();

    const auto& offsets = helper->recv.offsets;
    const int totalRecvd = offsets[helper->nBuffers];

    hov->resize_anew(totalRecvd * ov->objSize);
    unpacker->update(hov, stream);

    const int nthreads = 256;
    const int nblocks = totalRecvd;
    const size_t shMemSize = offsets.size() * sizeof(offsets[0]);
    
    mpark::visit([&](auto unpackerHandler)
    {
        SAFE_KERNEL_LAUNCH(
            ObjectHaloExchangeKernels::unpackObjects,
            nblocks, nthreads, shMemSize, stream,
            helper->wrapRecvData(), unpackerHandler );
    }, ExchangersCommon::getHandler(unpacker));
}

PinnedBuffer<int>& ObjectHaloExchanger::getSendOffsets(int id)
{
    return helpers[id]->send.offsets;
}

PinnedBuffer<int>& ObjectHaloExchanger::getRecvOffsets(int id)
{
    return helpers[id]->recv.offsets;
}

DeviceBuffer<MapEntry>& ObjectHaloExchanger::getMap(int id)
{
    return maps[id];
}
