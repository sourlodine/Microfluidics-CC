#pragma once

#include "interface.h"

class ObjectVector;
class LocalObjectVector;

class ObjectsPacker : public Packer
{
public:
    ObjectsPacker(const YmrState *state, ObjectVector *ov, PackPredicate predicate);

    size_t getPackedSizeBytes(int n) const override;

    void packToBuffer(const LocalObjectVector *lov, const DeviceBuffer<MapEntry>& map, const PinnedBuffer<int>& sizes,
                      const PinnedBuffer<int>& offsets, char *buffer, cudaStream_t stream);
    
    void unpackFromBuffer(LocalObjectVector *lov, const PinnedBuffer<int>& offsets, const PinnedBuffer<int>& sizes,
                          const char *buffer, int oldObjSize, cudaStream_t stream);

protected:
    ObjectVector *ov;
};
