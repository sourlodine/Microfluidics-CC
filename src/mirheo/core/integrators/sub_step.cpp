#include "sub_step.h"

#include "forcing_terms/none.h"
#include "vv.h"

#include <mirheo/core/interactions/interface.h>
#include <mirheo/core/logger.h>
#include <mirheo/core/pvs/particle_vector.h>
#include <mirheo/core/utils/common.h>
#include <mirheo/core/utils/config.h>

#include <memory>

namespace mirheo
{
IntegratorSubStep::IntegratorSubStep(const MirState *state, std::string name, int substeps,
                                     const std::vector<Interaction*>& fastForces) :
    Integrator(state, name),
    fastForces(fastForces),
    subIntegrator(std::make_unique<IntegratorVV<Forcing_None>> (state, name + "_sub", Forcing_None())),
    subState(*state),
    substeps(substeps)
{
    std::string ffNames = "";

    if (fastForces.size() == 0)
        die("Integrator '%s' needs at least one integration", name.c_str());
    
    for (auto ff : fastForces)
    {
        if (!ff->isSelfObjectInteraction())
            die("IntegratorSubStep '%s': expects a self-interaction (given '%s').",
                name.c_str(), ff->name.c_str());

        ffNames += "'" + ff->name + "' ";
    }

    debug("setup substep integrator '%s' for %d substeps with sub integrator '%s' and fast forces '%s'",
          name.c_str(), substeps, subIntegrator->name.c_str(), ffNames.c_str());

    updateSubState();
    
    subIntegrator->setState(&subState);
}

IntegratorSubStep::~IntegratorSubStep() = default;

Config IntegratorSubStep::getConfig() const {
    return Config::Dictionary{
        {"__type", "IntegratorSubStep"},
        {"name", name},
        {"fastForces", fastForces},  // Only pointers.
        {"subIntegrator", *subIntegrator},
        {"substeps", substeps},
    };
}

void IntegratorSubStep::stage1(__UNUSED ParticleVector *pv, __UNUSED cudaStream_t stream)
{}

void IntegratorSubStep::stage2(ParticleVector *pv, cudaStream_t stream)
{
    // save "slow forces"
    slowForces.copyFromDevice(pv->local()->forces(), stream);
    
    // save previous positions
    previousPositions.copyFromDevice(pv->local()->positions(), stream);

    // advance with internal vv integrator

    updateSubState();

    // save fastForces state and reset it afterwards
    auto *savedStatePtr = fastForces[0]->getState();

    for (auto& ff : fastForces)
        ff->setState(&subState);
    
    for (int substep = 0; substep < substeps; ++substep)
    {
        if (substep != 0)
            pv->local()->forces().copy(slowForces, stream);        

        for (auto ff : fastForces)
            ff->local(pv, pv, nullptr, nullptr, stream);
        
        subIntegrator->stage2(pv, stream);

        subState.currentTime += subState.dt;
        subState.currentStep ++;
    }
    
    // restore previous positions into old_particles channel
    pv->local()->dataPerParticle.getData<real4>(ChannelNames::oldPositions)->copy(previousPositions, stream);

    // restore state of fastForces
    for (auto& ff : fastForces)
        ff->setState(savedStatePtr);

    invalidatePV(pv);
}

void IntegratorSubStep::setPrerequisites(ParticleVector *pv)
{
    // luckily do not need cell lists for self interactions
    for (auto ff : fastForces)
        ff->setPrerequisites(pv, pv, nullptr, nullptr);
}

void IntegratorSubStep::updateSubState()
{
    subState = *getState();
    subState.dt = getState()->dt / static_cast<real>(substeps);
}

} // namespace mirheo
