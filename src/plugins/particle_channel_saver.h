#pragma once

#include <string>
#include "interface.h"

class ParticleVector;

class ParticleChannelSaverPlugin : public SimulationPlugin
{
public:
    ParticleChannelSaverPlugin(const YmrState *state, std::string name, std::string pvName,
                               std::string channelName, std::string savedName);

    void beforeIntegration(cudaStream_t stream) override;
    
    bool needPostproc() override;

    void setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;

private:
    std::string pvName;
    ParticleVector *pv;
    std::string channelName, savedName;
};





