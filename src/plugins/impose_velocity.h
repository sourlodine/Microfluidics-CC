#pragma once

#include <plugins/interface.h>
#include <core/containers.h>
#include <vector>
#include <string>

#include <core/utils/folders.h>
#include <core/utils/pytypes.h>

class ParticleVector;

class ImposeVelocityPlugin : public SimulationPlugin
{
public:
    ImposeVelocityPlugin(const YmrState *state, std::string name, std::vector<std::string> pvNames,
                         float3 low, float3 high, float3 targetVel, int every);

    void setup(Simulation* simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;
    void afterIntegration(cudaStream_t stream) override;

    bool needPostproc() override { return false; }
    
    void setTargetVelocity(PyTypes::float3 v);
    
private:
    std::vector<std::string> pvNames;
    std::vector<ParticleVector*> pvs;

    float3 high, low;
    float3 targetVel;

    int every;

    PinnedBuffer<int> nSamples{1};
    PinnedBuffer<double3> totVel{1};
};

