#pragma once

#include "interface.h"

class ObjectVector;
class LocalObjectVector;

class ObjectPacker : public Packer
{
public:
    ObjectPacker(ParticleVector *pv, LocalParticleVector *lpv, PackPredicate predicate);

    size_t getPackedSizeBytes(int n) override;

    void packToBuffer(const DeviceBuffer<MapEntry>& map, const PinnedBuffer<int>& sizes,
                      PinnedBuffer<size_t>& offsetsBytes, char *buffer, cudaStream_t stream);
    
    void unpackFromBuffer(PinnedBuffer<size_t>& offsetsBytes,
                          const PinnedBuffer<int>& offsets, const PinnedBuffer<int>& sizes,
                          const char *buffer, cudaStream_t stream);

protected:
    ObjectVector *ov;
    LocalObjectVector * lov;
};
