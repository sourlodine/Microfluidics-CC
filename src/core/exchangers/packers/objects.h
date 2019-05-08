#pragma once

#include "interface.h"

class ObjectVector;
class LocalObjectVector;
class ExchangeHelper;
struct BufferInfos;

class ObjectsPacker : public Packer
{
public:
    ObjectsPacker(ObjectVector *ov, PackPredicate predicate);

    size_t getPackedSizeBytes(int n) const override;

    void packToBuffer(const LocalObjectVector *lov, const DeviceBuffer<MapEntry>& map, BufferInfos *helper, cudaStream_t stream);
    void unpackFromBuffer(LocalObjectVector *lov, const BufferInfos *helper, int oldObjSize, cudaStream_t stream);
    void unpackBulkFromBuffer(LocalObjectVector *lov, int bulkId, const BufferInfos *helper, cudaStream_t stream);

    void reversePackToBuffer(const LocalObjectVector *lov, BufferInfos *helper, cudaStream_t stream);
    void reverseUnpackFromBufferAndAdd(LocalObjectVector *lov, const DeviceBuffer<MapEntry>& map,
                                       const BufferInfos *helper, cudaStream_t stream);
    
protected:

    void _unpackFromBuffer(LocalObjectVector *lov, const BufferInfos *helper, int oldObjSize, int bufStart, int bufEnd, cudaStream_t stream);

    template <typename Pvisitor, typename Ovisitor>
    void _applyToChannels(const LocalObjectVector *lov, Pvisitor &&pvisitor, Ovisitor &&ovisitor);

    ObjectVector *ov;
};
