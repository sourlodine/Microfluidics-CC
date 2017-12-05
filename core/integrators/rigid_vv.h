#pragma once

#include "interface.h"

/**
 * Integrate motion of the rigid bodies.
 */
class IntegratorVVRigid : Integrator
{
public:
	void stage1(ParticleVector* pv, float t, cudaStream_t stream) override;
	void stage2(ParticleVector* pv, float t, cudaStream_t stream) override;

	void setPrerequisites(ParticleVector* pv) override;

	IntegratorVVRigid(std::string name, float dt) :
		Integrator(name, dt)
	{}

	~IntegratorVVRigid() = default;
};
