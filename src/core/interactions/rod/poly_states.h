#pragma once

#include "parameters.h"
#include "forces_kernels.h"
#include "states_kernels.h"

#include <core/pvs/rod_vector.h>
#include <core/pvs/views/rv.h>
#include <core/utils/cpu_gpu_defines.h>
#include <core/utils/cuda_common.h>
#include <core/utils/kernel_launch.h>

template <int Nstates>
static void updateStatesAndApplyForces(RodVector *rv,
                                       const GPU_RodBiSegmentParameters<Nstates> devParams,
                                       StatesParametersNone& stateParams, cudaStream_t stream)
{}


template <int Nstates>
static void updateStatesAndApplyForces(RodVector *rv,
                                       const GPU_RodBiSegmentParameters<Nstates> devParams,
                                       StatesSmoothingParameters& stateParams, cudaStream_t stream)
{
    RVview view(rv, rv->local());

    auto kappa = rv->local()->dataPerBisegment.getData<float4>(ChannelNames::rodKappa)->devPtr();
    auto tau_l = rv->local()->dataPerBisegment.getData<float2>(ChannelNames::rodTau_l)->devPtr();

    const int nthreads = 128;
    const int nblocks = view.nObjects;

    SAFE_KERNEL_LAUNCH(RodStatesKernels::findPolymorphicStates<Nstates>,
                       nblocks, nthreads, 0, stream,
                       view, devParams, kappa, tau_l);
}

static auto getGPUParams(StatesSpinParameters& p)
{
    GPU_SpinParameters dp;
    dp.J    = p.J;
    dp.kBT  = p.kBT;
    dp.beta = 1.0 /  p.kBT;
    dp.seed = p.generate();
    return dp;
}

template <int Nstates>
static void updateStatesAndApplyForces(RodVector *rv,
                                       const GPU_RodBiSegmentParameters<Nstates> devParams,
                                       StatesSpinParameters& stateParams, cudaStream_t stream)
{
    auto lrv = rv->local();
    RVview view(rv, lrv);

    auto kappa = lrv->dataPerBisegment.getData<float4>(ChannelNames::rodKappa)->devPtr();
    auto tau_l = lrv->dataPerBisegment.getData<float2>(ChannelNames::rodTau_l)->devPtr();

    auto& states = *lrv->dataPerBisegment.getData<int>(ChannelNames::polyStates);
    states.clear(stream);

    // initialize to ground energies without spin interactions
    {
        const int nthreads = 128;
        const int nblocks = view.nObjects;
        
        SAFE_KERNEL_LAUNCH(RodStatesKernels::findPolymorphicStates<Nstates>,
                           nblocks, nthreads, 0, stream,
                           view, devParams, kappa, tau_l);
    }
    
    const int nthreads = 512;
    const int nblocks = view.nObjects;

    // TODO check if it fits into shared mem
    const size_t shMemSize = sizeof(states[0]) * (view.nSegments - 1);
    
    for (int i = 0; i < stateParams.nsteps; ++i)
    {
        auto devSpinParams = getGPUParams(stateParams);
        
        SAFE_KERNEL_LAUNCH(RodStatesKernels::findPolymorphicStatesMCStep<Nstates>,
                           nblocks, nthreads, shMemSize, stream,
                           view, devParams, devSpinParams, kappa, tau_l);
    }
}


