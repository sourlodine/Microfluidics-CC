#pragma once

#include <vector>
#include <string>

#include <plugins/interface.h>
#include <core/containers.h>
#include <core/datatypes.h>

#include <core/xdmf/xdmf.h>

class ParticleVector;
class CellList;

class ParticleSenderPlugin : public SimulationPlugin
{
public:

    enum class ChannelType {
        Scalar, Vector, Tensor6
    };
    
    ParticleSenderPlugin(const YmrState *state, std::string name, std::string pvName, int dumpEvery,
                         std::vector<std::string> channelNames,
                         std::vector<ChannelType> channelTypes);

    void setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;
    void handshake() override;

    void beforeForces(cudaStream_t stream) override;
    void serializeAndSend(cudaStream_t stream) override;

    bool needPostproc() override { return true; }
    
protected:
    std::string pvName;
    ParticleVector *pv;
    
    int dumpEvery;

    HostBuffer<Particle> particles;
    std::vector<std::string> channelNames;
    std::vector<ChannelType> channelTypes;
    std::vector<HostBuffer<float>> channelData;

    std::vector<char> sendBuffer;
};


class ParticleDumperPlugin : public PostprocessPlugin
{
public:
    ParticleDumperPlugin(std::string name, std::string path);

    void deserialize(MPI_Status& stat) override;
    void handshake() override;

protected:

    float _recvAndUnpack();
    
    int timeStamp = 0;
    const int zeroPadding = 5;
    std::string path;

    std::vector<Particle> particles;
    std::vector<float> velocities;
    std::vector<int> ids;
    std::shared_ptr<std::vector<float>> positions;

    std::vector<XDMF::Channel> channels;
    std::vector<std::vector<float>> channelData;
};
