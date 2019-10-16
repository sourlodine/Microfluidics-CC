#pragma once

#include "interface.h"

#include <core/containers.h>
#include <core/pvs/object_deleter.h>


class ObjectToParticlesPlugin : public SimulationPlugin
{
public:
    ObjectToParticlesPlugin(const MirState *state, std::string name, std::string ovName, std::string pvName, float4 plane);
    ~ObjectToParticlesPlugin();

    void setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;
    void afterIntegration(cudaStream_t stream) override;

    bool needPostproc() override { return false; }

protected:
    std::string ovName;
    std::string pvName;
    ObjectVector   *ov;  // From.
    ParticleVector *pv;  // To.

    ObjectDeleter deleter;
    float4 plane;  // Local coordinate system.
};
