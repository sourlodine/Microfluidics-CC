#pragma once

#include "interface.h"

#include <core/containers.h>

class ParticleVector;
class CellList;


template<class InsideWallChecker>
class SimpleStationaryWall : public Wall
{
public:
	SimpleStationaryWall(std::string name, InsideWallChecker&& insideWallChecker) :
		Wall(name), insideWallChecker(std::move(insideWallChecker))
	{	}

	void setup(MPI_Comm& comm, float3 globalDomainSize, float3 globalDomainStart, float3 localDomainSize) override;

	void removeInner(ParticleVector* pv) override;
	void attach(ParticleVector* pv, CellList* cl, int check=0) override;
	void bounce(float dt, cudaStream_t stream) override;

	void check(cudaStream_t stream) override;

private:
	MPI_Comm wallComm;

	InsideWallChecker insideWallChecker;

	std::vector<ParticleVector*> particleVectors;
	std::vector<CellList*> cellLists;

	std::vector<int> checkEvery, nBounceCalls;

	std::vector<DeviceBuffer<int>*> boundaryCells;
	PinnedBuffer<int> nInside{1};
};
