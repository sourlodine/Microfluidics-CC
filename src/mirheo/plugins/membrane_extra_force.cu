#include "membrane_extra_force.h"

#include <core/utils/kernel_launch.h>
#include <core/pvs/membrane_vector.h>
#include <core/pvs/views/ov.h>
#include <core/simulation.h>

#include <core/utils/cuda_common.h>

namespace MembraneExtraForcesKernels
{
__global__ void addForce(OVview view, const Force *forces)
{
    int gid = blockIdx.x * blockDim.x + threadIdx.x;
    if (gid >= view.size) return;

    int locId = gid % view.objSize;

    view.forces[gid] += forces[locId].toReal4();
}
} // namespace MembraneExtraForcesKernels

MembraneExtraForcePlugin::MembraneExtraForcePlugin(const MirState *state, std::string name, std::string pvName, const std::vector<real3>& forces) :
    SimulationPlugin(state, name),
    pvName(pvName),
    forces(forces.size())
{
    HostBuffer<Force> hostForces(forces.size());

    for (size_t i = 0; i < forces.size(); ++i)
        hostForces[i].f = forces[i];
    
    this->forces.copy(hostForces, 0);
}

void MembraneExtraForcePlugin::setup(Simulation *simulation, const MPI_Comm& comm, const MPI_Comm& interComm)
{
    SimulationPlugin::setup(simulation, comm, interComm);

    auto pv_ptr = simulation->getPVbyNameOrDie(pvName);
    if ( !(pv = dynamic_cast<MembraneVector*>(pv_ptr)) )
        die("MembraneExtraForcePlugin '%s' expects a MembraneVector (given '%s')", name.c_str(), pvName.c_str());
}

void MembraneExtraForcePlugin::beforeForces(cudaStream_t stream)
{
    OVview view(pv, pv->local());
    const int nthreads = 128;

    SAFE_KERNEL_LAUNCH(
        MembraneExtraForcesKernels::addForce,
        getNblocks(view.size, nthreads), nthreads, 0, stream,
        view, forces.devPtr() );
}

