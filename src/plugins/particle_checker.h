#pragma once

#include <plugins/interface.h>
#include <core/containers.h>
#include <core/datatypes.h>

#include <vector>

class ParticleVector;

class ParticleCheckerPlugin : public SimulationPlugin
{
public:
    ParticleCheckerPlugin(const YmrState *state, std::string name, int checkEvery);
    ~ParticleCheckerPlugin();

    void setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;
    
    void afterIntegration(cudaStream_t stream) override;

    bool needPostproc() override { return false; }

    enum class Info {Ok, Out, Nan};
    enum {GOOD, BAD};
    
    struct __align__(16) ParticleStatus
    {
        int tag, id;
        Info info;
    };

private:
    int checkEvery;
    
    PinnedBuffer<ParticleStatus> statuses;
    std::vector<ParticleVector*> pvs;
};
