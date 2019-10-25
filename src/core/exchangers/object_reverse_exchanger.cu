#include "object_reverse_exchanger.h"
#include "object_halo_exchanger.h"
#include "exchange_helpers.h"
#include "utils/common.h"

#include <core/logger.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/rod_vector.h>
#include <core/pvs/packers/objects.h>
#include <core/utils/kernel_launch.h>

namespace ObjectReverseExchangerKernels
{

template <class PackerHandler>
__global__ void reversePack(BufferOffsetsSizesWrap dataWrap, PackerHandler packer)
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

    const int dstObjId = objId - offsets[bufId];
    const int srcObjId = objId;

    packer.blockPack(numElements, buffer, srcObjId, dstObjId);
}

template <class PackerHandler>
__global__ void reverseUnpackAndAdd(PackerHandler packer, const MapEntry *map,
                                    BufferOffsetsSizesWrap dataWrap)
{
    constexpr real eps = 1e-6_r;
    const int objId       = blockIdx.x;
    
    const MapEntry mapEntry = map[objId];
    const int bufId    = mapEntry.getBufId();
    const int dstObjId = mapEntry.getId();
    const int srcObjId = objId - dataWrap.offsets[bufId];
    const int numElements = dataWrap.sizes[bufId];
    
    auto buffer = dataWrap.getBuffer(bufId);

    packer.blockUnpackAddNonZero(numElements, buffer, srcObjId, dstObjId, eps);
}

} // namespace ObjectReverseExchangerKernels


ObjectReverseExchanger::ObjectReverseExchanger(ObjectHaloExchanger *entangledHaloExchanger) :
    entangledHaloExchanger(entangledHaloExchanger)
{}

ObjectReverseExchanger::~ObjectReverseExchanger() = default;

void ObjectReverseExchanger::attach(ObjectVector *ov, std::vector<std::string> channelNames)
{
    const int id = objects.size();
    objects.push_back(ov);

    auto rv = dynamic_cast<RodVector*>(ov);
    
    PackPredicate predicate = [channelNames](const DataManager::NamedChannelDesc& namedDesc)
    {
        return std::find(channelNames.begin(),
                         channelNames.end(),
                         namedDesc.first)
            != channelNames.end();
    };

    std::unique_ptr<ObjectPacker> packer, unpacker;

    if (rv == nullptr)
    {
        packer   = std::make_unique<ObjectPacker>(predicate);
        unpacker = std::make_unique<ObjectPacker>(predicate);
    }
    else
    {
        packer   = std::make_unique<RodPacker>(predicate);
        unpacker = std::make_unique<RodPacker>(predicate);
    }
    
    auto helper = std::make_unique<ExchangeHelper>(ov->name, id, packer.get());
    
    packers  .push_back(std::move(  packer));
    unpackers.push_back(std::move(unpacker));
    helpers  .push_back(std::move(  helper));

    std::string allChannelNames = channelNames.size() ? "channels " : "no channels.";
    for (const auto& name : channelNames)
        allChannelNames += "'" + name + "' ";

    info("Object vector '%s' was attached to reverse halo exchanger with %s",
         ov->name.c_str(), allChannelNames.c_str());
}

bool ObjectReverseExchanger::needExchange(__UNUSED int id)
{
    return true;
}

void ObjectReverseExchanger::prepareSizes(int id, __UNUSED cudaStream_t stream)
{
    auto  helper  = helpers[id].get();
    auto& offsets = entangledHaloExchanger->getRecvOffsets(id);
    
    for (int i = 0; i < helper->nBuffers; ++i)
        helper->send.sizes[i] = offsets[i+1] - offsets[i];
}

void ObjectReverseExchanger::prepareData(int id, cudaStream_t stream)
{
    auto ov     = objects[id];
    auto hov    = ov->halo();
    auto helper = helpers[id].get();
    auto packer = packers[id].get();
    
    debug2("Preparing '%s' data to reverse send", ov->name.c_str());

    packer->update(hov, stream);

    helper->computeSendOffsets();
    helper->send.uploadInfosToDevice(stream);
    helper->resizeSendBuf();

    const auto& offsets = helper->send.offsets;
    const int nSendObj = offsets[helper->nBuffers];
    
    const int nthreads = 256;
    const int nblocks = nSendObj;

    const size_t shMemSize = offsets.size() * sizeof(offsets[0]);

    mpark::visit([&](auto packerHandler)
    {
        SAFE_KERNEL_LAUNCH(
            ObjectReverseExchangerKernels::reversePack,
            nblocks, nthreads, shMemSize, stream,
            helper->wrapSendData(), packerHandler );
    }, ExchangersCommon::getHandler(packer));
    
    debug2("Will send back data for %d objects", nSendObj);
}

void ObjectReverseExchanger::combineAndUploadData(int id, cudaStream_t stream)
{
    auto ov       = objects[id];
    auto lov      = ov->local();
    auto helper   =   helpers[id].get();
    auto unpacker = unpackers[id].get();

    unpacker->update(lov, stream);

    const int totalRecvd = helper->recv.offsets[helper->nBuffers];
    auto& map = entangledHaloExchanger->getMap(id);

    debug("Updating data for %d '%s' objects", totalRecvd, ov->name.c_str());

    const int nthreads = 256;
        
    mpark::visit([&](auto unpackerHandler)
    {
        SAFE_KERNEL_LAUNCH(
            ObjectReverseExchangerKernels::reverseUnpackAndAdd,
            map.size(), nthreads, 0, stream,
            unpackerHandler, map.devPtr(),
            helper->wrapRecvData());
    }, ExchangersCommon::getHandler(unpacker));
}
