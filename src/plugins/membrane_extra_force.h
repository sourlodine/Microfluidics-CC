#pragma once

#include <array>
#include <vector>
#include <string>

#include <plugins/interface.h>
#include <core/containers.h>
#include <core/datatypes.h>
#include <core/utils/pytypes.h>

class MembraneVector;

class MembraneExtraForcePlugin : public SimulationPlugin
{
public:

    MembraneExtraForcePlugin(std::string name, std::string pvName, const PyContainer &forces);

    void setup(Simulation* sim, const MPI_Comm& comm, const MPI_Comm& interComm) override;
    void beforeForces(cudaStream_t stream) override;

    bool needPostproc() override { return false; }

private:
    std::string pvName;
    MembraneVector *pv;
    DeviceBuffer<Force> forces;
};

