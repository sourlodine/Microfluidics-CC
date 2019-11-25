#pragma once

#include <mirheo/core/containers.h>
#include <mirheo/core/plugins.h>

#include <memory>
#include <string>

namespace mirheo
{

class ParticleVector;
class ParticlePacker;

class ExchangePVSFluxPlanePlugin : public SimulationPlugin
{
public:
    ExchangePVSFluxPlanePlugin(const MirState *state, std::string name, std::string pv1Name, std::string pv2Name, real4 plane);
    ~ExchangePVSFluxPlanePlugin();

    void setup(Simulation* simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;
    void beforeCellLists(cudaStream_t stream) override;

    bool needPostproc() override { return false; }

private:
    std::string pv1Name, pv2Name;
    ParticleVector *pv1, *pv2;
    real4 plane;

    PinnedBuffer<int> numberCrossedParticles;
    std::unique_ptr<ParticlePacker> extra1, extra2;
};

} // namespace mirheo
