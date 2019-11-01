#include "membrane.h"

#include "membrane/kernels/common.h"
#include "membrane/kernels/dihedral/kantor.h"
#include "membrane/kernels/dihedral/juelicher.h"
#include "membrane/kernels/triangle/lim.h"
#include "membrane/kernels/triangle/wlc.h"
#include "membrane/impl.h"

#include <mirheo/core/pvs/membrane_vector.h>
#include <mirheo/core/pvs/views/ov.h>
#include <mirheo/core/utils/cuda_common.h>
#include <mirheo/core/utils/kernel_launch.h>

namespace mirheo
{


namespace MembraneInteractionKernels
{
__global__ void computeAreaAndVolume(OVviewWithAreaVolume view, MeshView mesh)
{
    const int objId = blockIdx.x;
    const int offset = objId * mesh.nvertices;
    real2 a_v = make_real2(0.0_r);

    for (int i = threadIdx.x; i < mesh.ntriangles; i += blockDim.x) {
        const int3 ids = mesh.triangles[i];

        const auto v0 = make_mReal3(make_real3( view.readPosition(offset + ids.x) ));
        const auto v1 = make_mReal3(make_real3( view.readPosition(offset + ids.y) ));
        const auto v2 = make_mReal3(make_real3( view.readPosition(offset + ids.z) ));

        a_v.x += triangleArea(v0, v1, v2);
        a_v.y += triangleSignedVolume(v0, v1, v2);
    }

    a_v = warpReduce( a_v, [] (real a, real b) { return a+b; } );

    if (laneId() == 0)
        atomicAdd(&view.area_volumes[objId], a_v);
}
} // namespace MembraneInteractionKernels

MembraneInteraction::MembraneInteraction(const MirState *state, std::string name, CommonMembraneParameters commonParams,
                                         VarBendingParams bendingParams, VarShearParams shearParams,
                                         bool stressFree, real growUntil) :
    Interaction(state, name, /* default cutoff rc */ 1.0)
{
    mpark::visit([&](auto bePrms, auto shPrms)
    {                     
        using DihedralForce = typename decltype(bePrms)::DihedralForce;
        
        if (stressFree)
        {
            using TriangleForce = typename decltype(shPrms)::TriangleForce <StressFreeState::Active>;
            
            impl = std::make_unique<MembraneInteractionImpl<TriangleForce, DihedralForce>>
                (state, name, commonParams, shPrms, bePrms, growUntil);
        }
        else                         
        {
            using TriangleForce = typename decltype(shPrms)::TriangleForce <StressFreeState::Inactive>;
            
            impl = std::make_unique<MembraneInteractionImpl<TriangleForce, DihedralForce>>
                (state, name, commonParams, shPrms, bePrms, growUntil);
        }
        
    }, bendingParams, shearParams);
}

MembraneInteraction::~MembraneInteraction() = default;

void MembraneInteraction::setPrerequisites(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2)
{
    if (pv1 != pv2)
        die("Internal membrane forces can't be computed between two different particle vectors");

    auto ov = dynamic_cast<MembraneVector*>(pv1);
    if (ov == nullptr)
        die("Internal membrane forces can only be computed with a MembraneVector");

    ov->requireDataPerObject<real2>(ChannelNames::areaVolumes, DataManager::PersistenceMode::None);

    impl->setPrerequisites(pv1, pv2, cl1, cl2);
}

void MembraneInteraction::local(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream)
{
    if (impl.get() == nullptr)
        die("%s needs a concrete implementation, none was provided", name.c_str());

    precomputeQuantities(pv1, stream);
    impl->local(pv1, pv2, cl1, cl2, stream);
}

void MembraneInteraction::halo(ParticleVector *pv1,
                               __UNUSED ParticleVector *pv2,
                               __UNUSED CellList *cl1,
                               __UNUSED CellList *cl2,
                               __UNUSED cudaStream_t stream)
{
    debug("Not computing internal membrane forces between local and halo membranes of '%s'",
          pv1->name.c_str());
}

bool MembraneInteraction::isSelfObjectInteraction() const
{
    return true;
}

void MembraneInteraction::precomputeQuantities(ParticleVector *pv1, cudaStream_t stream)
{
    auto ov = dynamic_cast<MembraneVector *>(pv1);

    if (ov->objSize != ov->mesh->getNvertices())
        die("Object size of '%s' (%d) and number of vertices (%d) mismatch",
            ov->name.c_str(), ov->objSize, ov->mesh->getNvertices());

    debug("Computing areas and volumes for %d cells of '%s'",
          ov->local()->nObjects, ov->name.c_str());

    OVviewWithAreaVolume view(ov, ov->local());

    MembraneMeshView mesh(static_cast<MembraneMesh*>(ov->mesh.get()));

    ov->local()
        ->dataPerObject.getData<real2>(ChannelNames::areaVolumes)
        ->clearDevice(stream);
    
    const int nthreads = 128;
    SAFE_KERNEL_LAUNCH(MembraneInteractionKernels::computeAreaAndVolume,
                       view.nObjects, nthreads, 0, stream,
                       view, mesh);
}

} // namespace mirheo
