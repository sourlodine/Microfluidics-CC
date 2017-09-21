#include "uniform.h"

#include <random>

#include <core/pvs/particle_vector.h>
#include <core/logger.h>

void UniformIC::exec(const MPI_Comm& comm, ParticleVector* pv, float3 globalDomainStart, float3 localDomainSize, cudaStream_t stream)
{
	int3 ncells = make_int3( ceilf(localDomainSize) );
	float3 h = localDomainSize / make_float3(ncells);

	float volume = h.x*h.y*h.z;
	float avg = volume * density;
	int predicted = round(avg * ncells.x*ncells.y*ncells.z * 1.05);
	pv->local()->resize(predicted, stream, ResizeKind::resizeAnew);

	int rank;
	MPI_Check( MPI_Comm_rank(comm, &rank) );

	std::hash<std::string> nameHash;
	const int seed = rank + nameHash(pv->name);
	std::mt19937 gen(seed);
	std::poisson_distribution<> particleDistribution(avg);
	std::uniform_real_distribution<float> udistr(0, 1);

	int mycount = 0;
	auto cooPtr = pv->local()->coosvels.hostPtr();
	for (int i=0; i<ncells.x; i++)
		for (int j=0; j<ncells.y; j++)
			for (int k=0; k<ncells.z; k++)
			{
				int nparts = particleDistribution(gen);
				for (int p=0; p<nparts; p++)
				{
					pv->local()->resize(mycount+1, stream, ResizeKind::resizePreserve);
					cooPtr[mycount].r.x = i*h.x - 0.5*localDomainSize.x + udistr(gen);
					cooPtr[mycount].r.y = j*h.y - 0.5*localDomainSize.y + udistr(gen);
					cooPtr[mycount].r.z = k*h.z - 0.5*localDomainSize.z + udistr(gen);
					cooPtr[mycount].i1 = mycount;

					cooPtr[mycount].u.x = 0*udistr(gen);
					cooPtr[mycount].u.y = 0*udistr(gen);
					cooPtr[mycount].u.z = 0*udistr(gen);

					cooPtr[mycount].i1 = mycount;
					mycount++;
				}
			}

	pv->globalDomainStart = globalDomainStart;
	pv->localDomainSize = localDomainSize;

	int totalCount=0; // TODO: int64!
	MPI_Check( MPI_Exscan(&mycount, &totalCount, 1, MPI_INT, MPI_SUM, comm) );
	for (int i=0; i < pv->local()->size(); i++)
		cooPtr[i].i1 += totalCount;

	pv->local()->coosvels.uploadToDevice(stream);

	debug2("Generated %d %s particles", pv->local()->size(), pv->name.c_str());
}
