// Yo ho ho ho
#define private public
#define protected public

#include <core/pvs/particle_vector.h>
#include <core/celllist.h>
#include <core/mpi/api.h>
#include <core/logger.h>

#include <core/containers.h>

#include <core/initial_conditions/uniform_ic.h>

Logger logger;

Particle addShift(Particle p, float a, float b, float c)
{
	Particle res = p;
	res.r.x += a;
	res.r.y += b;
	res.r.z += c;

	return res;
}

int main(int argc, char ** argv)
{
	// Init

	int nranks, rank;
	int ranks[] = {1, 1, 1};
	int periods[] = {1, 1, 1};
	MPI_Comm cartComm;

	MPI_Init(&argc, &argv);
	logger.init(MPI_COMM_WORLD, "redist.log", 9);

	MPI_Check( MPI_Comm_size(MPI_COMM_WORLD, &nranks) );
	MPI_Check( MPI_Comm_rank(MPI_COMM_WORLD, &rank) );
	MPI_Check( MPI_Cart_create(MPI_COMM_WORLD, 3, ranks, periods, 0, &cartComm) );

	float3 length{80,70,55};
	float3 domainStart = -length / 2.0f;
	const float rc = 1.0f;
	ParticleVector dpds("dpd", 1.0f);
	CellList* cells = new PrimaryCellList (&dpds, rc, length);

	InitialConditions* ic = new UniformIC(8.0);
	ic->exec(MPI_COMM_WORLD, &dpds, {0,0,0}, length, 0);

	const int initialNP = dpds.local()->size();
	HostBuffer<Particle> host(dpds.local()->size());
	const float dt = 0.1;
	for (int i=0; i<dpds.local()->size(); i++)
	{
		dpds.local()->coosvels[i].u.x = 10*(drand48() - 0.5);
		dpds.local()->coosvels[i].u.y = 10*(drand48() - 0.5);
		dpds.local()->coosvels[i].u.z = 10*(drand48() - 0.5);

		dpds.local()->coosvels[i].r += dt * dpds.local()->coosvels[i].u;

		host[i] = dpds.local()->coosvels[i];
	}

	dpds.local()->coosvels.uploadToDevice(0);

	ParticleRedistributor redist(cartComm);
	cells->build(0);
	redist.attach(&dpds, cells);

	for (int i=0; i<1; i++)
	{
		redist.init(0);
		cudaStreamSynchronize(0);
		redist.finalize(0);

		dpds.redistValid = false;
	}

	std::vector<Particle> bufs[27];

	for (int i=0; i<initialNP; i++)
	{
		Particle& p = host[i];

		int3 code = cells->getCellIdAlongAxes<false>(p.r);
		int cx = code.x,  cy = code.y,  cz = code.z;
		auto ncells = cells->ncells;

		// 8
		if (cx == -1         && cy == -1         && cz == -1)         { bufs[ (0*3 + 0)*3 + 0 ].push_back(addShift(p,  length.x,  length.y,  length.z)); continue; }
		if (cx == -1         && cy == -1         && cz == ncells.z  ) { bufs[ (2*3 + 0)*3 + 0 ].push_back(addShift(p,  length.x,  length.y, -length.z)); continue; }
		if (cx == -1         && cy == ncells.y   && cz == -1)         { bufs[ (0*3 + 2)*3 + 0 ].push_back(addShift(p,  length.x, -length.y,  length.z)); continue; }
		if (cx == -1         && cy == ncells.y   && cz == ncells.z  ) { bufs[ (2*3 + 2)*3 + 0 ].push_back(addShift(p,  length.x, -length.y, -length.z)); continue; }
		if (cx == ncells.x   && cy == -1         && cz == -1)         { bufs[ (0*3 + 0)*3 + 2 ].push_back(addShift(p, -length.x,  length.y,  length.z)); continue; }
		if (cx == ncells.x   && cy == -1         && cz == ncells.z  ) { bufs[ (2*3 + 0)*3 + 2 ].push_back(addShift(p, -length.x,  length.y, -length.z)); continue; }
		if (cx == ncells.x   && cy == ncells.y   && cz == -1)         { bufs[ (0*3 + 2)*3 + 2 ].push_back(addShift(p, -length.x, -length.y,  length.z)); continue; }
		if (cx == ncells.x   && cy == ncells.y   && cz == ncells.z  ) { bufs[ (2*3 + 2)*3 + 2 ].push_back(addShift(p, -length.x, -length.y, -length.z)); continue; }

		// 12
		if (cx == -1         && cy == -1)         { bufs[ (1*3 + 0)*3 + 0 ].push_back(addShift(p,  length.x,  length.y,         0)); continue; }
		if (cx == ncells.x   && cy == -1)         { bufs[ (1*3 + 0)*3 + 2 ].push_back(addShift(p, -length.x,  length.y,         0)); continue; }
		if (cx == -1         && cy == ncells.y  ) { bufs[ (1*3 + 2)*3 + 0 ].push_back(addShift(p,  length.x, -length.y,         0)); continue; }
		if (cx == ncells.x   && cy == ncells.y  ) { bufs[ (1*3 + 2)*3 + 2 ].push_back(addShift(p, -length.x, -length.y,         0)); continue; }

		if (cy == -1         && cz == -1)         { bufs[ (0*3 + 0)*3 + 1 ].push_back(addShift(p,         0,  length.y,  length.z)); continue; }
		if (cy == ncells.y   && cz == -1)         { bufs[ (0*3 + 2)*3 + 1 ].push_back(addShift(p,         0, -length.y,  length.z)); continue; }
		if (cy == -1         && cz == ncells.z  ) { bufs[ (2*3 + 0)*3 + 1 ].push_back(addShift(p,         0,  length.y, -length.z)); continue; }
		if (cy == ncells.y   && cz == ncells.z  ) { bufs[ (2*3 + 2)*3 + 1 ].push_back(addShift(p,         0, -length.y, -length.z)); continue; }


		if (cz == -1         && cx == -1)         { bufs[ (0*3 + 1)*3 + 0 ].push_back(addShift(p,  length.x,         0,  length.z)); continue; }
		if (cz == ncells.z   && cx == -1)         { bufs[ (2*3 + 1)*3 + 0 ].push_back(addShift(p,  length.x,         0, -length.z)); continue; }
		if (cz == -1         && cx == ncells.x  ) { bufs[ (0*3 + 1)*3 + 2 ].push_back(addShift(p, -length.x,         0,  length.z)); continue; }
		if (cz == ncells.z   && cx == ncells.x  ) { bufs[ (2*3 + 1)*3 + 2 ].push_back(addShift(p, -length.x,         0, -length.z)); continue; }

		// 6
		if (cx == -1)         { bufs[ (1*3 + 1)*3 + 0 ].push_back(addShift(p,  length.x,         0,         0)); continue; }
		if (cx == ncells.x  ) { bufs[ (1*3 + 1)*3 + 2 ].push_back(addShift(p, -length.x,         0,         0)); continue; }
		if (cy == -1)         { bufs[ (1*3 + 0)*3 + 1 ].push_back(addShift(p,         0,  length.y,         0)); continue; }
		if (cy == ncells.y  ) { bufs[ (1*3 + 2)*3 + 1 ].push_back(addShift(p,         0, -length.y,         0)); continue; }
		if (cz == -1)         { bufs[ (0*3 + 1)*3 + 1 ].push_back(addShift(p,         0,         0,  length.z)); continue; }
		if (cz == ncells.z  ) { bufs[ (2*3 + 1)*3 + 1 ].push_back(addShift(p,         0,         0, -length.z)); continue; }
	}

	for (int i = 0; i<27; i++)
	{
		//if (bufs[i].size() != redist.helpers[0]->sendSizes[i])
			printf("%2d-th redist differs in size: %5d, expected %5d\n", i, redist.helpers[0]->sendSizes[i], (int)bufs[i].size());

		std::vector<Particle> got, reference;

		auto cmp = [] (Particle a, Particle b) {
			if (a.i1 < b.i1) return true;
			if (a.i1 > b.i1) return false;

			if (a.r.x > b.r.x + 1e-6) return true;
			if (a.r.y > b.r.y + 1e-6) return true;
			if (a.r.z > b.r.z + 1e-6) return true;

			return false;
		};

		auto& helper = redist.helpers[0];
		std::sort(bufs[i].begin(), bufs[i].end(), cmp);
		std::sort((Particle*)helper->sendBuf.hostPtr() + helper->sendOffsets[i],
				  (Particle*)helper->sendBuf.hostPtr() + helper->sendOffsets[i+1], cmp);

		std::set_difference(bufs[i].begin(), bufs[i].end(),
				(Particle*)helper->sendBuf.hostPtr() + helper->sendOffsets[i], (Particle*)helper->sendBuf.hostPtr() + helper->sendOffsets[i+1],
				std::inserter(reference, reference.begin()), cmp);

		std::set_difference(
				(Particle*)helper->sendBuf.hostPtr() + helper->sendOffsets[i], (Particle*)helper->sendBuf.hostPtr() + helper->sendOffsets[i+1],
				bufs[i].begin(), bufs[i].end(),
				std::inserter(got, got.begin()), cmp);

		for (int pid = 0; pid < std::max(reference.size(), got.size()); pid++)
		{
			if (pid < got.size())
				printf("redist %2d:  %5d [%12.5e %12.5e %12.5e], ",
					i, got[pid].i1, got[pid].r.x, got[pid].r.y, got[pid].r.z);
			else
				printf("redist none,                                           ");

			printf(" expected ");

			if (pid < reference.size())
				printf("%5d [%12.5e %12.5e %12.5e]\n",
						reference[pid].i1, reference[pid].r.x, reference[pid].r.y, reference[pid].r.z);
			else
				printf("none\n");
		}
	}

	return 0;
}
