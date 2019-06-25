#pragma once

#include "interface.h"
#include "rod/forces_kernels.h"
#include "rod/parameters.h"

#include <core/pvs/rod_vector.h>
#include <core/pvs/views/rv.h>
#include <core/utils/cpu_gpu_defines.h>
#include <core/utils/cuda_common.h>
#include <core/utils/kernel_launch.h>

static auto getBoundParams(const RodParameters& p)
{
    GPU_RodBoundsParameters dp;
    dp.ksCenter = p.ksCenter;
    dp.ksFrame  = p.ksFrame;
    dp.lcenter  = p.l0;
    dp.lcross   = p.a0;
    dp.lring    = 0.5 * sqrt(2.0) * p.a0;
    dp.ldiag    = 0.5 * sqrt(p.a0*p.a0 + p.l0*p.l0);
    return dp;
}

template <int Nstates>
static auto getBiSegmentParams(const RodParameters& p)
{
    GPU_RodBiSegmentParameters<Nstates> dp;
    dp.kBending = p.kBending;
    dp.kTwist   = p.kTwist;

    for (size_t i = 0; i < p.kappaEq.size(); ++i)
    {
        dp.kappaEq[i]  = p.kappaEq[i];
        dp.tauEq[i]    = p.tauEq[i];
        dp.groundE[i]  = p.groundE[i];
    }
    return dp;
}

template <int Nstates>
class InteractionRodImpl : public Interaction
{
public:
    InteractionRodImpl(const YmrState *state, std::string name, RodParameters parameters, bool saveEnergies) :
        Interaction(state, name, /* rc */ 1.0f),
        parameters(parameters),
        saveEnergies(saveEnergies)
    {}

    ~InteractionRodImpl() = default;

    void setPrerequisites(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2) override
    {
        auto rv1 = dynamic_cast<RodVector *> (pv1);

        if (saveEnergies) rv1->requireDataPerBisegment<float>(ChannelNames::energies,   DataManager::PersistenceMode::None);

        if (Nstates > 1)
        {
            rv1->requireDataPerBisegment<int>  (ChannelNames::polyStates, DataManager::PersistenceMode::None);
            rv1->requireDataPerBisegment<float4>  (ChannelNames::rodKappa, DataManager::PersistenceMode::None);
            rv1->requireDataPerBisegment<float2>  (ChannelNames::rodTau_l, DataManager::PersistenceMode::None);
        }
    }
    
    void local(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream) override
    {
        auto rv = dynamic_cast<RodVector *>(pv1);

        debug("Computing internal rod forces for %d rods of '%s'",
              rv->local()->nObjects, rv->name.c_str());

        RVview view(rv, rv->local());

        {
            const int nthreads = 128;
            const int nblocks  = getNblocks(view.nObjects * view.nSegments, nthreads);
        
            auto devParams = getBoundParams(parameters);
        
            SAFE_KERNEL_LAUNCH(RodForcesKernels::computeRodBoundForces,
                               nblocks, nthreads, 0, stream,
                               view, devParams);
        }

        {
            auto devParams = getBiSegmentParams<Nstates>(parameters);

            if (Nstates > 1)
            {
                auto kappa = rv->local()->dataPerBisegment.getData<float4>(ChannelNames::rodKappa)->devPtr();
                auto tau_l = rv->local()->dataPerBisegment.getData<float2>(ChannelNames::rodTau_l)->devPtr();

                int nthreads = 128;
                int nblocks  = getNblocks(view.nObjects * (view.nSegments-1), nthreads);
                
                SAFE_KERNEL_LAUNCH(RodForcesKernels::computeBisegmentData,
                                   nblocks, nthreads, 0, stream,
                                   view, kappa, tau_l);


                nthreads = 128;
                nblocks = view.nObjects;
                
                SAFE_KERNEL_LAUNCH(RodForcesKernels::findPolymorphicStates<Nstates>,
                                   nblocks, nthreads, 0, stream,
                                   view, devParams, kappa, tau_l);
            }

            const int nthreads = 128;
            const int nblocks  = getNblocks(view.nObjects * (view.nSegments-1), nthreads);

            SAFE_KERNEL_LAUNCH(RodForcesKernels::computeRodBiSegmentForces<Nstates>,
                               nblocks, nthreads, 0, stream,
                               view, devParams, saveEnergies);
        }
    }

    void halo(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream)
    {}
    
protected:

    RodParameters parameters;

    bool saveStates, saveEnergies;
};
