#pragma once

#include "object_vector.h"

#include <core/containers.h>
#include <core/datatypes.h>

class LocalRodVector : public LocalObjectVector
{
public:
    LocalRodVector(ParticleVector *pv, int objSize, int nObjects = 0);
    virtual ~LocalRodVector();

    void resize(int np, cudaStream_t stream) override;
    void resize_anew(int np) override;

    int getNumSegmentsPerRod() const;

    DeviceBuffer<float4> bishopQuaternions;
    DeviceBuffer<float3> bishopFrames;
};


class RodVector: public ObjectVector
{
public:
    RodVector(const YmrState *state, std::string name, float mass, int nSegments, int nObjects = 0);
    ~RodVector();

    void updateBishopFrame(cudaStream_t stream);

    LocalRodVector* local() { return static_cast<LocalRodVector*>(ParticleVector::local()); }
    LocalRodVector* halo()  { return static_cast<LocalRodVector*>(ParticleVector::halo());  }
};
