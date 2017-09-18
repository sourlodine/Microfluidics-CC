#pragma once

#include <functional>
#include <core/xml/pugixml.hpp>

class ParticleVector;

struct InitialConditions
{
	virtual void exec(const MPI_Comm& comm, ParticleVector* pv, float3 globalDomainStart, float3 localDomainSize, cudaStream_t stream) = 0;

	virtual ~InitialConditions() = default;
};

struct DummyIC : public InitialConditions
{
	void exec(const MPI_Comm& comm, ParticleVector* pv, float3 globalDomainStart, float3 localDomainSize, cudaStream_t stream) override
	{ }

	virtual ~DummyIC() = default;
};


struct UniformIC : InitialConditions
{
	float mass, density;

	UniformIC(pugi::xml_node node);

	void exec(const MPI_Comm& comm, ParticleVector* pv, float3 globalDomainStart, float3 localDomainSize, cudaStream_t stream) override;

	~UniformIC() = default;
};

struct EllipsoidIC : InitialConditions
{
	float mass;
	float3 axes;
	float distance;
	int nObjs, objSize;
	std::string xyzfname;

	EllipsoidIC(pugi::xml_node node);

	void readXYZ(std::string fname, PinnedBuffer<Particle>& positions);
	void exec(const MPI_Comm& comm, ParticleVector* pv, float3 globalDomainStart, float3 localDomainSize, cudaStream_t stream) override;

	~EllipsoidIC() = default;
};
