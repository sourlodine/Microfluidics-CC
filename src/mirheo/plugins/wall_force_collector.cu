#include "wall_force_collector.h"
#include "utils/simple_serializer.h"
#include "utils/time_stamp.h"

#include <mirheo/core/datatypes.h>
#include <mirheo/core/pvs/particle_vector.h>
#include <mirheo/core/pvs/views/pv.h>
#include <mirheo/core/simulation.h>
#include <mirheo/core/utils/cuda_common.h>
#include <mirheo/core/utils/kernel_launch.h>
#include <mirheo/core/walls/interface.h>

namespace mirheo
{

namespace WallForceCollector
{
__global__ void totalForce(PVview view, double3 *totalForce)
{
    int tid = blockIdx.x * blockDim.x + threadIdx.x;

    real3 f {0._r, 0._r, 0._r};
    
    if (tid < view.size)
        f = make_real3(view.forces[tid]);

    f = warpReduce(f, [](real a, real b) { return a + b; });

    if (laneId() == 0)
        atomicAdd(totalForce, make_double3(f));
}
} //namespace WallForceCollector


WallForceCollectorPlugin::WallForceCollectorPlugin(const MirState *state, std::string name,
                                                   std::string wallName, std::string frozenPvName,
                                                   int sampleEvery, int dumpEvery) :
    SimulationPlugin(state, name),
    sampleEvery(sampleEvery),
    dumpEvery(dumpEvery),
    wallName(wallName),
    frozenPvName(frozenPvName)
{}

WallForceCollectorPlugin::~WallForceCollectorPlugin() = default;


void WallForceCollectorPlugin::setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm)
{
    SimulationPlugin::setup(simulation, comm, interComm);

    wall = dynamic_cast<SDF_basedWall*>(simulation->getWallByNameOrDie(wallName));

    if (wall == nullptr)
        die("Plugin '%s' expects a SDF based wall (got '%s')\n", name.c_str(), wallName.c_str());

    pv = simulation->getPVbyNameOrDie(frozenPvName);

    bounceForceBuffer = wall->getCurrentBounceForce();
}

void WallForceCollectorPlugin::afterIntegration(cudaStream_t stream)
{   
    if (isTimeEvery(getState(), sampleEvery))
    {
        pvForceBuffer.clear(stream);

        PVview view(pv, pv->local());
        const int nthreads = 128;

        SAFE_KERNEL_LAUNCH(
            WallForceCollector::totalForce,
            getNblocks(view.size, nthreads), nthreads, 0, stream,
            view, pvForceBuffer.devPtr() );

        pvForceBuffer     .downloadFromDevice(stream);
        bounceForceBuffer->downloadFromDevice(stream);

        totalForce += pvForceBuffer[0];
        totalForce += (*bounceForceBuffer)[0];

        ++nsamples;
    }
    
    needToDump = (isTimeEvery(getState(), dumpEvery) && nsamples > 0);
}

void WallForceCollectorPlugin::serializeAndSend(__UNUSED cudaStream_t stream)
{
    if (needToDump)
    {
        waitPrevSend();
        SimpleSerializer::serialize(sendBuffer, getState()->currentTime, nsamples, totalForce);
        send(sendBuffer);
        needToDump = false;
        nsamples   = 0;
        totalForce = make_double3(0, 0, 0);
    }
}

WallForceDumperPlugin::WallForceDumperPlugin(std::string name, std::string filename) :
    PostprocessPlugin(name)
{
    auto status = fdump.open(filename, "w");
    if (status != FileWrapper::Status::Success)
        die("Could not open file '%s'", filename.c_str());
}

void WallForceDumperPlugin::deserialize()
{
    MirState::TimeType currentTime;
    int nsamples;
    double localForce[3], totalForce[3] = {0.0, 0.0, 0.0};

    SimpleSerializer::deserialize(data, currentTime, nsamples, localForce);
    
    MPI_Check( MPI_Reduce(localForce, totalForce, 3, MPI_DOUBLE, MPI_SUM, 0, comm) );

    if (rank == 0)
    {
        totalForce[0] /= (double)nsamples;
        totalForce[1] /= (double)nsamples;
        totalForce[2] /= (double)nsamples;

        fprintf(fdump.get(), "%g %g %g %g\n",
                currentTime, totalForce[0], totalForce[1], totalForce[2]);
        fflush(fdump.get());
    }
}

} // namespace mirheo
