#pragma once

#include <string>
#include "datatypes.h"

class CellList;

struct ParticleVector
{
	int np;
	float mass;
	std::string name;

	PinnedBuffer<Particle> coosvels, pingPongCoosvels;
	//PinnedBuffer<Force> forces, pingPongForces;
	DeviceBuffer<Force> forces, pingPongForces;

	float3 domainStart, domainLength; // assume 0,0,0 is center of the local domain

	PinnedBuffer<Particle> halo;
	CellList* activeCL;

	ParticleVector(std::string name) : name(name), activeCL(nullptr)
	{
		resize(0);
	}

	int size()
	{
		return np;
	}

	void pushStreamWOhalo(cudaStream_t stream)
	{
		coosvels.pushStream(stream);
		pingPongCoosvels.pushStream(stream);
		forces.pushStream(stream);
		pingPongForces.pushStream(stream);
	}

	void popStreamWOhalo()
	{
		coosvels.popStream();
		pingPongCoosvels.popStream();
		forces.popStream();
		pingPongForces.popStream();
	}

	void resize(const int n, ResizeKind kind = ResizeKind::resizePreserve)
	{
		coosvels.resize(n, kind);
		pingPongCoosvels.resize(n, kind);
		forces.resize(n, kind);
		pingPongForces.resize(n, kind);

		np = n;
	}
};

class ObjectVector: public ParticleVector
{
	DeviceBuffer<int> objStarts;
};

class UniformObjectVector: public ObjectVector
{

};
