#include "average_flow.h"

#include <core/utils/kernel_launch.h>
#include <core/simulation.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/views/pv.h>
#include <core/celllist.h>
#include <core/utils/cuda_common.h>

#include "simple_serializer.h"
#include "sampling_helpers.h"

namespace average_flow_kernels {

__global__ void sample(
        PVview pvView, CellListInfo cinfo,
        float* avgDensity,
        ChannelsInfo channelsInfo)
{
    const int pid = threadIdx.x + blockIdx.x*blockDim.x;
    if (pid >= pvView.size) return;

    Particle p(pvView.particles, pid);

    int cid = cinfo.getCellId(p.r);

    atomicAdd(avgDensity + cid, 1);

    sampling_helpers_kernels::sampleChannels(pid, cid, channelsInfo);
}

}

Average3D::Average3D(std::string name,
        std::vector<std::string> pvNames,
        std::vector<std::string> channelNames, std::vector<Average3D::ChannelType> channelTypes,
        int sampleEvery, int dumpEvery, float3 binSize) :
    SimulationPlugin(name), pvNames(pvNames),
    sampleEvery(sampleEvery), dumpEvery(dumpEvery), binSize(binSize),
    nSamples(0)
{
    channelsInfo.n = channelTypes.size();
    channelsInfo.types.resize_anew(channelsInfo.n);
    channelsInfo.average.resize(channelsInfo.n);
    channelsInfo.averagePtrs.resize_anew(channelsInfo.n);
    channelsInfo.dataPtrs.resize_anew(channelsInfo.n);

    for (int i=0; i<channelsInfo.n; i++)
        channelsInfo.types[i] = channelTypes[i];

    channelsInfo.names = channelNames;
}

void Average3D::setup(Simulation* sim, const MPI_Comm& comm, const MPI_Comm& interComm)
{
    SimulationPlugin::setup(sim, comm, interComm);

    domain = sim->domain;
    // TODO: this should be reworked if the domains are allowed to have different size
    resolution = make_int3( floorf(domain.localSize / binSize) );
    binSize = domain.localSize / make_float3(resolution);

    const int total = resolution.x * resolution.y * resolution.z;

    density.resize_anew(total);
    density.clear(0);
    std::string allChannels("density");
    for (int i=0; i<channelsInfo.n; i++)
    {
        if      (channelsInfo.types[i] == Average3D::ChannelType::Scalar)  channelsInfo.average[i].resize_anew(1*total);
        else if (channelsInfo.types[i] == Average3D::ChannelType::Tensor6) channelsInfo.average[i].resize_anew(6*total);
        else                                                               channelsInfo.average[i].resize_anew(3*total);

        channelsInfo.average[i].clear(0);
        channelsInfo.averagePtrs[i] = channelsInfo.average[i].devPtr();

        allChannels += ", " + channelsInfo.names[i];
    }

    channelsInfo.averagePtrs.uploadToDevice(0);
    channelsInfo.types.uploadToDevice(0);


    for (const auto& pvName : pvNames)
        pvs.push_back(sim->getPVbyNameOrDie(pvName));

    info("Plugin '%s' initialized for the %d PVs and channels %s, resolution %dx%dx%d",
         name.c_str(), pvs.size(), allChannels.c_str(),
         resolution.x, resolution.y, resolution.z);
}

void Average3D::sampleOnePv(ParticleVector *pv, cudaStream_t stream)
{
    CellListInfo cinfo(binSize, pv->domain.localSize);
    PVview pvView(pv, pv->local());
    ChannelsInfo gpuInfo(channelsInfo, pv, stream);

    const int nthreads = 128;
    SAFE_KERNEL_LAUNCH(
            average_flow_kernels::sample,
            getNblocks(pvView.size, nthreads), nthreads, 0, stream,
            pvView, cinfo, density.devPtr(), gpuInfo);
}

void Average3D::afterIntegration(cudaStream_t stream)
{
    if (currentTimeStep % sampleEvery != 0 || currentTimeStep == 0) return;

    debug2("Plugin %s is sampling now", name.c_str());

    for (auto& pv : pvs) sampleOnePv(pv, stream);    

    nSamples++;
}

void Average3D::scaleSampled(cudaStream_t stream)
{
    const int nthreads = 128;
    // Order is important here! First channels, only then dens

    for (int i=0; i<channelsInfo.n; i++)
    {
        auto& data = channelsInfo.average[i];
        int sz = density.size();
        int components = 3;
        if (channelsInfo.types[i] == ChannelType::Scalar)  components = 1;
        if (channelsInfo.types[i] == ChannelType::Tensor6) components = 6;

        SAFE_KERNEL_LAUNCH(
                sampling_helpers_kernels::scaleVec,
                getNblocks(sz, nthreads), nthreads, 0, stream,
                sz, components, data.devPtr(), density.devPtr() );

        data.downloadFromDevice(stream, ContainersSynch::Asynch);
        data.clearDevice(stream);
    }

    int sz = density.size();
    SAFE_KERNEL_LAUNCH(
            sampling_helpers_kernels::scaleDensity,
            getNblocks(sz, nthreads), nthreads, 0, stream,
            sz, density.devPtr(), /* pv->mass */ 1.0 / (nSamples * binSize.x*binSize.y*binSize.z) );

    density.downloadFromDevice(stream, ContainersSynch::Synch);
    density.clearDevice(stream);

    nSamples = 0;
}

void Average3D::serializeAndSend(cudaStream_t stream)
{
    if (currentTimeStep % dumpEvery != 0 || currentTimeStep == 0) return;
    if (nSamples == 0) return;
    
    scaleSampled(stream);

    debug2("Plugin '%s' is now packing the data", name.c_str());
    SimpleSerializer::serialize(sendBuffer, currentTime, density, channelsInfo.average);
    send(sendBuffer);
}

void Average3D::handshake()
{
    std::vector<char> data;
    std::vector<int> sizes;

    for (auto t : channelsInfo.types)
        switch (t)
        {
            case ChannelType::Scalar:
                sizes.push_back(1);
                break;
            case ChannelType::Tensor6:
                sizes.push_back(6);
                break;
            default:
                sizes.push_back(3);
                break;
        }
    
    SimpleSerializer::serialize(data, sim->nranks3D, sim->rank3D, resolution, binSize, sizes, channelsInfo.names);
    send(data);
}

