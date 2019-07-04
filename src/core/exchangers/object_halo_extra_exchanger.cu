#include "object_halo_extra_exchanger.h"
#include "object_halo_exchanger.h"
#include "exchange_helpers.h"

#include <core/logger.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/packers/objects.h>
#include <core/pvs/views/ov.h>
#include <core/utils/kernel_launch.h>

namespace ObjectHaloExtraExchangerKernels
{
__global__ void pack(const OVview view, ObjectPackerHandler packer,
                     const MapEntry *map, BufferOffsetsSizesWrap dataWrap)
{
    int tid         = threadIdx.x;
    int dstObjId    = blockIdx.x;
    int numElements = gridDim.x;

    auto mapEntry = map[dstObjId];

    const int bufId    = mapEntry.getBufId();
    const int srcObjId = mapEntry.getId();
    
    auto buffer = dataWrap.buffer + dataWrap.offsetsBytes[bufId];

    size_t offsetBytes = 0;
    
    for (int pid = tid; pid < view.objSize; pid += blockDim.x)
    {
        int srcId = srcObjId * view.objSize + pid;
        int dstId = dstObjId * view.objSize + pid;

        offsetBytes = packer.particles.pack(srcId, dstId, buffer,
                                            numElements * view.objSize);
    }

    buffer += offsetBytes;
    if (tid == 0)
        packer.objects.pack(srcObjId, dstObjId, buffer, numElements);    
}

__global__ void unpack(const char *buffer, int startDstObjId,
                       OVview view, ObjectPackerHandler packer)
{
    const int objId = blockIdx.x;
    const int tid   = threadIdx.x;
    const int numElements = gridDim.x;

    const int srcObjId = objId;
    const int dstObjId = objId + startDstObjId;
    
    size_t offsetBytes = 0;
    
    for (int pid = tid; pid < view.objSize; pid += blockDim.x)
    {
        const int dstPid = dstObjId * view.objSize + pid;
        const int srcPid = srcObjId * view.objSize + pid;
        offsetBytes = packer.particles.unpack(srcPid, dstPid, buffer,
                                              numElements * view.objSize);
    }

    buffer += offsetBytes;
    
    if (tid == 0)
        packer.objects.unpack(srcObjId, dstObjId, buffer, numElements);
}
} // namespace ObjectHaloExtraExchangerKernels


ObjectExtraExchanger::ObjectExtraExchanger(ObjectHaloExchanger *entangledHaloExchanger) :
    entangledHaloExchanger(entangledHaloExchanger)
{}

ObjectExtraExchanger::~ObjectExtraExchanger() = default;

bool ObjectExtraExchanger::needExchange(int id)
{
    return true;
}

void ObjectExtraExchanger::attach(ObjectVector *ov, const std::vector<std::string>& extraChannelNames)
{
    int id = objects.size();
    objects.push_back(ov);

    PackPredicate predicate = [extraChannelNames](const DataManager::NamedChannelDesc& namedDesc)
    {
        return std::find(extraChannelNames.begin(),
                         extraChannelNames.end(),
                         namedDesc.first)
            != extraChannelNames.end();
    };
    
    auto   packer = std::make_unique<ObjectPacker>(predicate);
    auto unpacker = std::make_unique<ObjectPacker>(predicate);
    auto   helper = std::make_unique<ExchangeHelper>(ov->name, id, packer.get());

    packers  .push_back(std::move(  packer));
    unpackers.push_back(std::move(unpacker));
    helpers  .push_back(std::move(  helper));
}

void ObjectExtraExchanger::prepareSizes(int id, cudaStream_t stream)
{
    auto helper = helpers[id].get();
    auto packer = packers[id].get();
    auto ov = objects[id];

    packer->update(ov->local(), stream);

    const auto& offsets = entangledHaloExchanger->getSendOffsets(id);

    for (int i = 0; i < helper->nBuffers; ++i)
        helper->send.sizes[i] = offsets[i+1] - offsets[i];
}

void ObjectExtraExchanger::prepareData(int id, cudaStream_t stream)
{
    auto ov     = objects[id];
    auto helper = helpers[id].get();
    auto packer = packers[id].get();
    auto& map   = entangledHaloExchanger->getMap(id);

    helper->computeSendOffsets();
    helper->send.uploadInfosToDevice(stream);
    helper->resizeSendBuf();

    OVview ovView(ov, ov->local());

    const int nthreads = 256;
    
    SAFE_KERNEL_LAUNCH(
        ObjectHaloExtraExchangerKernels::pack,
        map.size(), nthreads, 0, stream,
        ovView, packer->handler(), map.devPtr(),
        helper->wrapSendData() );
}

void ObjectExtraExchanger::combineAndUploadData(int id, cudaStream_t stream)
{
    auto ov       = objects[id];
    auto helper   = helpers[id].get();
    auto unpacker = unpackers[id].get();

    int totalRecvd = helper->recv.offsets[helper->nBuffers];

    ov->halo()->resize_anew(totalRecvd * ov->objSize);
    OVview ovView(ov, ov->local());
    
    unpacker->update(ov->halo(), stream);

    // TODO different streams
    for (int bufId = 0; bufId < helper->nBuffers; ++bufId)
    {
        int nObjs = helper->recv.sizes[bufId];

        if (bufId == helper->bulkId || nObjs == 0) continue;

        const int nthreads = 256;
        
        SAFE_KERNEL_LAUNCH(
            ObjectHaloExtraExchangerKernels::unpack,
            nObjs, nthreads, 0, stream,
            helper->recv.buffer.devPtr() + helper->recv.offsetsBytes[bufId],
            helper->recv.offsets[bufId],
            ovView, unpacker->handler() );
    }
}
