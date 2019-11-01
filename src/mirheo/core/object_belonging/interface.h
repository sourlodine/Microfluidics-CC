#pragma once

#include <mirheo/core/mirheo_object.h>

#include <cuda_runtime.h>
#include <mpi.h>
#include <string>
#include <vector>

namespace mirheo
{

class ParticleVector;
class ObjectVector;
class CellList;

class ObjectBelongingChecker : public MirSimulationObject
{
public:
    ObjectBelongingChecker(const MirState *state, std::string name);
    virtual ~ObjectBelongingChecker();

    virtual void splitByBelonging(ParticleVector *src, ParticleVector *pvIn, ParticleVector *pvOut, cudaStream_t stream) = 0;
    virtual void checkInner(ParticleVector *pv, CellList *cl, cudaStream_t stream) = 0;
    virtual void setup(ObjectVector *ov) = 0;

    virtual std::vector<std::string> getChannelsToBeExchanged() const;
    virtual ObjectVector* getObjectVector() = 0;
};

} // namespace mirheo
