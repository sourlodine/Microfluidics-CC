#pragma once

#include <core/domain.h>
#include <core/datatypes.h>
#include <mpi.h>

class ParticleVector;

class VelocityField_Translate
{
public:
	VelocityField_Translate(float3 vel) :
		vel(vel)
	{	}

	void setup(MPI_Comm& comm, DomainInfo domain) { }

	const VelocityField_Translate& handler() const { return *this; }

	__device__ __forceinline__ float3 operator()(float3 coo) const
	{
		return vel;
	}

private:
	float3 vel;

	DomainInfo domain;
};
