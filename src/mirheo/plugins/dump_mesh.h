#pragma once

#include <mirheo/core/containers.h>
#include <mirheo/core/datatypes.h>
#include <mirheo/core/plugins.h>

#include <vector>

namespace mirheo
{

class ParticleVector;
class ObjectVector;
class CellList;

class MeshPlugin : public SimulationPlugin
{
public:
    MeshPlugin(const MirState *state, std::string name, std::string ovName, int dumpEvery);
    MeshPlugin(const MirState *state, Loader&, const ConfigObject&);

    void setup(Simulation* simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;

    void beforeForces(cudaStream_t stream) override;
    void serializeAndSend(cudaStream_t stream) override;

    bool needPostproc() override { return true; }
    void saveSnapshotAndRegister(Saver&) override;

protected:
    ConfigObject _saveSnapshot(Saver&, const std::string& typeName);

private:
    std::string ovName_;
    int dumpEvery_;

    std::vector<char> sendBuffer_;
    std::vector<real3> vertices_;
    PinnedBuffer<real4>* srcVerts_;

    ObjectVector *ov_;
};


class MeshDumper : public PostprocessPlugin
{
public:
    MeshDumper(std::string name, std::string path);
    MeshDumper(Loader&, const ConfigObject&);
    ~MeshDumper();

    void deserialize() override;
    void setup(const MPI_Comm& comm, const MPI_Comm& interComm) override;
    void saveSnapshotAndRegister(Saver&) override;

protected:
    ConfigObject _saveSnapshot(Saver&, const std::string& typeName);

private:
    std::string path_;

    bool activated_{true};

    std::vector<int3> connectivity_;
    std::vector<real3> vertices_;
};

} // namespace mirheo
