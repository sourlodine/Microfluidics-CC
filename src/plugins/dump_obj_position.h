#pragma once

#include <plugins/interface.h>
#include <core/containers.h>
#include <core/datatypes.h>

#include <vector>

#include <core/pvs/object_vector.h>
#include <core/rigid_kernels/rigid_motion.h>


class ObjPositionsPlugin : public SimulationPlugin
{
public:
    ObjPositionsPlugin(const YmrState *state, std::string name, std::string ovName, int dumpEvery);

    void setup(Simulation* simulation, const MPI_Comm& comm, const MPI_Comm& interComm) override;

    void afterIntegration(cudaStream_t stream) override;
    void serializeAndSend(cudaStream_t stream) override;
    void handshake() override;

    bool needPostproc() override { return true; }

private:
    std::string ovName;
    int dumpEvery;
    bool needToSend = false;
    
    HostBuffer<int> ids;
    HostBuffer<LocalObjectVector::COMandExtent> coms;
    HostBuffer<RigidMotion> motions;
    TimeType savedTime = 0;

    std::vector<char> sendBuffer;

    ObjectVector* ov;
};


class ObjPositionsDumper : public PostprocessPlugin
{
public:
    ObjPositionsDumper(std::string name, std::string path);

    void deserialize(MPI_Status& stat) override;
    void setup(const MPI_Comm& comm, const MPI_Comm& interComm) override;
    void handshake() override;

    ~ObjPositionsDumper() {};

private:
    std::string path;
    int3 nranks3D;

    bool activated = true;
    MPI_File fout;
};
