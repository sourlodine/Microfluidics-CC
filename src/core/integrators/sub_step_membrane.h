#pragma once

#include "interface.h"

#include <core/containers.h>
#include <core/datatypes.h>

#include "forcing_terms/none.h"
#include "vv.h"

class Interaction;
class InteractionMembrane;

class IntegratorSubStepMembrane : Integrator
{
public:
    IntegratorSubStepMembrane(const YmrState *state, std::string name, int substeps, Interaction *fastForces);
    ~IntegratorSubStepMembrane();
    
    void stage1(ParticleVector* pv, cudaStream_t stream) override;
    void stage2(ParticleVector* pv, cudaStream_t stream) override;

    void setPrerequisites(ParticleVector* pv) override;        

private:

    InteractionMembrane *fastForces; /* interactions (self) called `substeps` times per time step */
    int substeps; /* number of substeps */
    DeviceBuffer<Force> slowForces;
    DeviceBuffer<Particle> previousPositions;
    std::unique_ptr<IntegratorVV<Forcing_None>> subIntegrator;
};
