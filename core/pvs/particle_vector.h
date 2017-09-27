#pragma once

#include <string>
#include <core/datatypes.h>
#include <core/containers.h>
#include <core/cuda_common.h>

class LocalParticleVector
{
protected:
	int np;

public:
	int changedStamp = 0;

	PinnedBuffer<Particle> coosvels;
	DeviceBuffer<Force> forces;

	// Local coordinate system; (0,0,0) is center of the local domain

	LocalParticleVector(int n=0, cudaStream_t stream = 0)
	{
		resize(n, stream);
	}

	int size()
	{
		return np;
	}

	virtual void resize(const int n, cudaStream_t stream, ResizeKind kind = ResizeKind::resizePreserve)
	{
		assert(n>=0);

		coosvels.resize(n, stream, kind);
		forces  .resize(n, stream, kind);

		np = n;
	}

	virtual ~LocalParticleVector() = default;
};

class ParticleVector
{
public:
	float3 localDomainSize, globalDomainStart;
	LocalParticleVector *_local, *_halo;

	float mass;
	std::string name;
	// Local coordinate system; (0,0,0) is center of the local domain

protected:
	ParticleVector(	std::string name, float mass, LocalParticleVector *local, LocalParticleVector *halo ) :
		name(name), mass(mass), _local(local), _halo(halo) {}

public:
	ParticleVector(std::string name, float mass, int n=0) :
		name(name), mass(mass),
		_local( new LocalParticleVector(n) ),
		_halo ( new LocalParticleVector(0) )
	{}

	LocalParticleVector* local() { return _local; }
	LocalParticleVector* halo()  { return _halo;  }

	virtual void checkpoint(MPI_Comm comm, std::string path);
	virtual void restart(MPI_Comm comm, std::string path);

	virtual ~ParticleVector() { delete _local; delete _halo; }
};


/**
 * GPU-compatibe struct of all the relevant data
 */
struct PVview
{
	float3 localDomainSize, globalDomainStart;

	int size;
	float4 *particles, *forces;

	float mass, invMass;


	__forceinline__ __host__ __device__ float3 local2global(float3 x) const
	{
		return x + globalDomainStart + 0.5f * localDomainSize;
	}
	__forceinline__ __host__ __device__ float3 global2local(float3 x) const
	{
		return x - globalDomainStart - 0.5f * localDomainSize;
	}


	PVview(ParticleVector* pv, LocalParticleVector* lpv)
	{
		localDomainSize = pv->localDomainSize;
		globalDomainStart = pv->globalDomainStart;

		size = lpv->size();
		particles = reinterpret_cast<float4*>(lpv->coosvels.devPtr());
		forces    = reinterpret_cast<float4*>(lpv->forces.devPtr());

		mass = pv->mass;
		invMass = 1.0 / mass;
	}
};
