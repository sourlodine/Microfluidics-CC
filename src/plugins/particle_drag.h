#pragma once

#include "interface.h"

class ParticleVector;

class ParticleDragPlugin : public SimulationPlugin
{
public:
    ParticleDragPlugin(const YmrState *state, std::string name, std::string pvName, float drag);

    void setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;
    void beforeForces(cudaStream_t stream) override;

    bool needPostproc() override { return false; }

private:
    std::string pvName;
    ParticleVector *pv;
    float drag;
};

