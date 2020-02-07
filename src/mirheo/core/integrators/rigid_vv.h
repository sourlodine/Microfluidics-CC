#pragma once

#include "interface.h"

namespace mirheo
{

/**
 * Integrate motion of the rigid bodies.
 */
class IntegratorVVRigid : public Integrator
{
public:
    IntegratorVVRigid(const MirState *state, const std::string& name);

    ~IntegratorVVRigid();

    void setPrerequisites(ParticleVector *pv) override;

    void execute(ParticleVector *pv, cudaStream_t stream) override;
};

} // namespace mirheo
