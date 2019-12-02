#include "wall_with_velocity.h"

#include "common_kernels.h"
#include "stationary_walls/box.h"
#include "stationary_walls/cylinder.h"
#include "stationary_walls/plane.h"
#include "stationary_walls/sdf.h"
#include "stationary_walls/sphere.h"
#include "velocity_field/oscillate.h"
#include "velocity_field/rotate.h"
#include "velocity_field/translate.h"

#include <mirheo/core/celllist.h>
#include <mirheo/core/logger.h>
#include <mirheo/core/pvs/object_vector.h>
#include <mirheo/core/pvs/particle_vector.h>
#include <mirheo/core/pvs/views/pv.h>
#include <mirheo/core/utils/cuda_common.h>
#include <mirheo/core/utils/kernel_launch.h>
#include <mirheo/core/utils/root_finder.h>

#include <cassert>
#include <cmath>
#include <fstream>
#include <texture_types.h>

namespace mirheo
{


template<typename VelocityField>
__global__ void imposeVelField(PVview view, const VelocityField velField)
{
    const int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= view.size) return;

    Particle p(view.readParticle(pid));

    p.u = velField(p.r);

    view.writeParticle(pid, p);
}

//===============================================================================================
// Member functions
//===============================================================================================

template<class InsideWallChecker, class VelocityField>
WallWithVelocity<InsideWallChecker, VelocityField>::WallWithVelocity
(std::string name, const MirState *state, InsideWallChecker&& insideWallChecker, VelocityField&& velField) :
    SimpleStationaryWall<InsideWallChecker>(name, state, std::move(insideWallChecker)),
    velField(std::move(velField))
{}


template<class InsideWallChecker, class VelocityField>
void WallWithVelocity<InsideWallChecker, VelocityField>::setup(MPI_Comm& comm)
{
    info("Setting up wall %s", this->name.c_str());

    CUDA_Check( cudaDeviceSynchronize() );

    this->insideWallChecker.setup(comm, this->getState()->domain);
    velField.setup(this->getState()->currentTime, this->getState()->domain);

    CUDA_Check( cudaDeviceSynchronize() );
}

template<class InsideWallChecker, class VelocityField>
void WallWithVelocity<InsideWallChecker, VelocityField>::attachFrozen(ParticleVector* pv)
{
    SimpleStationaryWall<InsideWallChecker>::attachFrozen(pv);

    const int nthreads = 128;
    PVview view(pv, pv->local());
    SAFE_KERNEL_LAUNCH(
            imposeVelField,
            getNblocks(view.size, nthreads), nthreads, 0, 0,
            view, velField.handler() );

    CUDA_Check( cudaDeviceSynchronize() );
}

template<class InsideWallChecker, class VelocityField>
void WallWithVelocity<InsideWallChecker, VelocityField>::bounce(cudaStream_t stream)
{
    real t  = this->getState()->currentTime;
    real dt = this->getState()->dt;
    
    velField.setup(t, this->getState()->domain);
    this->bounceForce.clear(stream);

    for (size_t i = 0; i < this->particleVectors.size(); ++i)
    {
        auto  pv = this->particleVectors[i];
        auto  cl = this->cellLists[i];
        auto& bc = this->boundaryCells[i];
        auto view = cl->CellList::getView<PVviewWithOldParticles>();

        debug2("Bouncing %d %s particles with wall velocity, %d boundary cells",
               pv->local()->size(), pv->name.c_str(), bc.size());

        const int nthreads = 64;
        SAFE_KERNEL_LAUNCH(
                BounceKernels::sdfBounce,
                getNblocks(bc.size(), nthreads), nthreads, 0, stream,
                view, cl->cellInfo(), bc.devPtr(), bc.size(), dt,
                this->insideWallChecker.handler(),
                velField.handler(),
                this->bounceForce.devPtr());

        CUDA_Check( cudaPeekAtLastError() );
    }
}


template class WallWithVelocity<StationaryWall_Sphere,   VelocityField_Rotate>;
template class WallWithVelocity<StationaryWall_Cylinder, VelocityField_Rotate>;
template class WallWithVelocity<StationaryWall_Plane,    VelocityField_Translate>;
template class WallWithVelocity<StationaryWall_Plane,    VelocityField_Oscillate>;

} // namespace mirheo
