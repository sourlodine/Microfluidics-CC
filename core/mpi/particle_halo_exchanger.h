#pragma once

#include <core/datatypes.h>
#include <core/logger.h>
#include <core/mpi/particle_exchanger.h>

#include <vector>

class ParticleVector;
class CellList;

class ParticleHaloExchanger : public ParticleExchanger
{
private:
	std::vector<CellList*> cellLists;
	std::vector<ParticleVector*> particles;

	void prepareData(int id, cudaStream_t defStream);
	void combineAndUploadData(int id);

public:
	ParticleHaloExchanger(MPI_Comm& comm) : ParticleExchanger(comm) {};

	void attach(ParticleVector* pv, CellList* cl);

	~ParticleHaloExchanger() = default;
};
