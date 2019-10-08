#include "pairwise.h"
#include "pairwise/factory_helper.h"
#include "pairwise/impl.h"
#include "pairwise/impl.stress.h"
#include "pairwise/kernels/density.h"
#include "pairwise/kernels/density_kernels.h"
#include "pairwise/kernels/dpd.h"
#include "pairwise/kernels/lj.h"
#include "pairwise/kernels/mdpd.h"
#include "pairwise/kernels/pressure_EOS.h"
#include "pairwise/kernels/sdpd.h"
#include "pairwise/kernels/type_traits.h"

#include <memory>

template <class KernelType>
static std::unique_ptr<Interaction>
createPairwiseFromKernel(const MirState *state, const std::string& name, float rc,
                         const typename std::enable_if<outputsForce<KernelType>::value, KernelType>::type& kernel,
                         const VarStressParams& varStressParams)
{
    if (mpark::holds_alternative<StressActiveParams>(varStressParams))
    {
        const auto stressParams = mpark::get<StressActiveParams>(varStressParams);
        return std::make_unique<InteractionPair_withStress<KernelType>>(state, name, rc, stressParams.period, kernel);
    }
    else
    {
        return std::make_unique<InteractionPair<KernelType>>(state, name, rc, kernel);
    }
}

template <class KernelType>
static std::unique_ptr<Interaction>
createPairwiseFromKernel(const MirState *state, const std::string& name, float rc, const KernelType& kernel, const VarStressParams& varStressParams)
{
    if (mpark::holds_alternative<StressActiveParams>(varStressParams))
        die("Incompatible interaction output: '%s' can not output stresses.", name.c_str());
    
    return std::make_unique<InteractionPair<KernelType>>(state, name, rc, kernel);
}


template <class Parameters>
static std::unique_ptr<Interaction>
createPairwiseFromParams(const MirState *state, const std::string& name, float rc, const Parameters& params, const VarStressParams& varStressParams)
{
    using KernelType = typename Parameters::KernelType;
    KernelType kernel(rc, params, state->dt);

    return createPairwiseFromKernel(state, name, rc, kernel, varStressParams);
}


std::unique_ptr<Interaction>
createPairwiseFromParams(const MirState *state, const std::string& name, float rc, const LJParams& params, const VarStressParams& varStressParams)
{
    return mpark::visit([&](auto& awareParams)
    {
        using AwareType = typename std::remove_reference<decltype(awareParams)>::type::KernelType;
        
        AwareType awareness(awareParams);
        PairwiseLJ<AwareType> lj(rc, params.epsilon, params.sigma, params.maxForce, awareness);

        return createPairwiseFromKernel(state, name, rc, lj, varStressParams);
    }, params.varLJAwarenessParams);
}

static std::unique_ptr<Interaction>
createPairwiseFromParams(const MirState *state, const std::string& name, float rc, const DensityParams& params, const VarStressParams& varStressParams)
{
    return mpark::visit([&](auto& densityKernelParams)
    {
        using DensityKernelType = typename std::remove_reference<decltype(densityKernelParams)>::type::KernelType;
        
        DensityKernelType densityKernel;
        PairwiseDensity<DensityKernelType> density(rc, densityKernel);

        return createPairwiseFromKernel(state, name, rc, density, varStressParams);
    }, params.varDensityKernelParams);
}

static std::unique_ptr<Interaction>
createPairwiseFromParams(const MirState *state, const std::string& name, float rc, const SDPDParams& params, const VarStressParams& varStressParams)
{
    return mpark::visit([&](auto& densityKernelParams, auto& EOSParams)
    {
        using DensityKernelType = typename std::remove_reference<decltype(densityKernelParams)>::type::KernelType;
        using EOSKernelType     = typename std::remove_reference<decltype(EOSParams          )>::type::KernelType;
        
        DensityKernelType density;
        EOSKernelType pressure(EOSParams);

        PairwiseSDPD<EOSKernelType, DensityKernelType> sdpd(rc, pressure, density, params.viscosity, params.kBT, state->dt);
        
        return createPairwiseFromKernel(state, name, rc, sdpd, varStressParams);
    }, params.varDensityKernelParams, params.varEOSParams);
}


PairwiseInteraction::PairwiseInteraction(const MirState *state, const std::string& name, float rc,
                                         const VarPairwiseParams& varParams, const VarStressParams& varStressParams) :
    Interaction(state, name, rc),
    varParams(varParams),
    varStressParams(varStressParams)
{
    impl = mpark::visit([&](const auto& params)
    {
        return createPairwiseFromParams(state, name, rc, params, varStressParams);
    }, varParams);
}

PairwiseInteraction::~PairwiseInteraction() = default;

void PairwiseInteraction::setPrerequisites(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2)
{
    impl->setPrerequisites(pv1, pv2, cl1, cl2);
}
    
void PairwiseInteraction::local(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream)
{
    impl->local(pv1, pv2, cl1, cl2, stream);
}

void PairwiseInteraction::halo(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream)
{
    impl->halo(pv1, pv2, cl1, cl2, stream);
}


Interaction::Stage PairwiseInteraction::getStage() const
{
    return impl->getStage();
}

std::vector<Interaction::InteractionChannel> PairwiseInteraction::getInputChannels() const
{
    return impl->getInputChannels();
}

std::vector<Interaction::InteractionChannel> PairwiseInteraction::getOutputChannels() const
{
    return impl->getOutputChannels();
}

void PairwiseInteraction::checkpoint(MPI_Comm comm, const std::string& path, int checkpointId)
{
    return impl->checkpoint(comm, path, checkpointId);
}

void PairwiseInteraction::restart(MPI_Comm comm, const std::string& path)
{
    return impl->restart(comm, path);
}

void PairwiseInteraction::setSpecificPair(__UNUSED const VarPairwiseParams& varParamsSpecific)
{
    
}
