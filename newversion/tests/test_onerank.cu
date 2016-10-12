// Yo ho ho ho
#define private public

#include "../core/containers.h"
#include "../core/celllist.h"
#include "../core/dpd.h"
#include "../core/halo_exchanger.h"
#include "../core/redistributor.h"
#include "../core/logger.h"
#include "../core/integrate.h"

#include <unistd.h>

Logger logger;

void makeCells(const Particle* __restrict__ coos, int* __restrict__ cellsStart, int* __restrict__ cellsSize,
		int3 ncells, float3 domainStart, float rc)
{

}

void forces(const Particle* __restrict__ coos, Acceleration* __restrict__ accs, const int* __restrict__ cellsStart, const int* __restrict__ cellsSize,
		int3 ncells, int totcells, float3 domainStart, float3 length)
{

	const float dt = 0.0025;
	const float kBT = 1.0;
	const float gammadpd = 20;
	const float sigma = sqrt(2 * gammadpd * kBT);
	const float sigmaf = sigma / sqrt(dt);
	const float aij = 50;

	auto addForce = [=] (int dstId, int srcId, Acceleration& a)
	{
		float _xr = coos[dstId].x[0] - coos[srcId].x[0];
		float _yr = coos[dstId].x[1] - coos[srcId].x[1];
		float _zr = coos[dstId].x[2] - coos[srcId].x[2];

		_xr = std::min({_xr, _xr - length.x, _xr + length.x});
		_yr = std::min({_yr, _yr - length.y, _yr + length.y});
		_zr = std::min({_zr, _zr - length.z, _zr + length.z});

		const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;

		if (rij2 > 1.0f) return;
		//assert(rij2 < 1);

		const float invrij = 1.0f / sqrt(rij2);
		const float rij = rij2 * invrij;
		const float argwr = 1.0f - rij;
		const float wr = argwr;

		const float xr = _xr * invrij;
		const float yr = _yr * invrij;
		const float zr = _zr * invrij;

		const float rdotv =
				xr * (coos[dstId].u[0] - coos[srcId].u[0]) +
				yr * (coos[dstId].u[1] - coos[srcId].u[1]) +
				zr * (coos[dstId].u[2] - coos[srcId].u[2]);

		const float myrandnr = 0;//Logistic::mean0var1(1, min(srcId, dstId), max(srcId, dstId));

		const float strength = aij * argwr - (gammadpd * wr * rdotv + sigmaf * myrandnr) * wr;

		a.a[0] += strength * xr;
		a.a[1] += strength * yr;
		a.a[2] += strength * zr;
	};

#pragma omp parallel for collapse(3)
	for (int cx = 0; cx < ncells.x; cx++)
		for (int cy = 0; cy < ncells.y; cy++)
			for (int cz = 0; cz < ncells.z; cz++)
			{
				const int cid = encode(cx, cy, cz, ncells);

				for (int dstId = cellsStart[cid]; dstId < cellsStart[cid] + cellsSize[cid]; dstId++)
				{
					Acceleration a {0,0,0,0};

					for (int dx = -1; dx <= 1; dx++)
						for (int dy = -1; dy <= 1; dy++)
							for (int dz = -1; dz <= 1; dz++)
							{
								int ncx, ncy, ncz;
								ncx = (cx+dx + ncells.x) % ncells.x;
								ncy = (cy+dy + ncells.y) % ncells.y;
								ncz = (cz+dz + ncells.z) % ncells.z;

								const int srcCid = encode(ncx, ncy, ncz, ncells);
								if (srcCid >= totcells || srcCid < 0) continue;

								for (int srcId = cellsStart[srcCid]; srcId < cellsStart[srcCid] + cellsSize[srcCid]; srcId++)
								{
									if (dstId != srcId)
										addForce(dstId, srcId, a);
								}
							}

					accs[dstId].a[0] = a.a[0];
					accs[dstId].a[1] = a.a[1];
					accs[dstId].a[2] = a.a[2];
				}
			}
}

int main(int argc, char ** argv)
{
	// Init

	int nranks, rank;
	int ranks[] = {1, 1, 1};
	int periods[] = {1, 1, 1};
	MPI_Comm cartComm;

	int provided;
	MPI_Init_thread(&argc, &argv, MPI_THREAD_MULTIPLE, &provided);
	if (provided < MPI_THREAD_MULTIPLE)
	{
	    printf("ERROR: The MPI library does not have full thread support\n");
	    MPI_Abort(MPI_COMM_WORLD, 1);
	}

	logger.init(MPI_COMM_WORLD, "onerank.log", 9);

	MPI_Check( MPI_Comm_size(MPI_COMM_WORLD, &nranks) );
	MPI_Check( MPI_Comm_rank(MPI_COMM_WORLD, &rank) );
	MPI_Check( MPI_Cart_create(MPI_COMM_WORLD, 3, ranks, periods, 0, &cartComm) );

	// Initial cells

	int3 ncells = {64, 64, 64};
	float3 domainStart = {-ncells.x / 2.0f, -ncells.y / 2.0f, -ncells.z / 2.0f};
	float3 length{(float)ncells.x, (float)ncells.y, (float)ncells.z};
	ParticleVector dpds(ncells, domainStart, length);

	const int ndens = 8;
	dpds.resize(ncells.x*ncells.y*ncells.z * ndens);

	srand48(0);

	printf("initializing...\n");

	int c = 0;
	for (int i=0; i<ncells.x; i++)
		for (int j=0; j<ncells.y; j++)
			for (int k=0; k<ncells.z; k++)
				for (int p=0; p<ndens; p++)
				{
					dpds.coosvels[c].x[0] = i + drand48() + domainStart.x;
					dpds.coosvels[c].x[1] = j + drand48() + domainStart.y;
					dpds.coosvels[c].x[2] = k + drand48() + domainStart.z;
					dpds.coosvels[c].i1 = c;

					dpds.coosvels[c].u[0] = drand48() - 0.5;
					dpds.coosvels[c].u[1] = drand48() - 0.5;
					dpds.coosvels[c].u[2] = drand48() - 0.5;
					c++;
				}


	dpds.resize(c);
	dpds.coosvels.synchronize(synchronizeDevice);
	dpds.accs.clear();

	HostBuffer<Particle> particles(dpds.np);
	for (int i=0; i<dpds.np; i++)
		particles[i] = dpds.coosvels[i];

	cudaStream_t defStream;
	CUDA_Check( cudaStreamCreateWithPriority(&defStream, cudaStreamNonBlocking, 10) );

	HaloExchanger halo(cartComm);
	halo.attach(&dpds, ndens);
	Redistributor redist(cartComm);
	redist.attach(&dpds, ndens);

	buildCellList(dpds,defStream);
	CUDA_Check( cudaStreamSynchronize(defStream) );

	const float dt = 0.001;
	const int niters = 100;

	for (int i=0; i<niters; i++)
	{
		dpds.accs.clear(defStream);
		computeInternalDPD(dpds, defStream);

		halo.exchangeInit();
		halo.exchangeFinalize();

		computeHaloDPD(dpds, defStream);
		CUDA_Check( cudaStreamSynchronize(defStream) );

		redist.redistribute(dt);

		buildCellListAndIntegrate(dpds, dt, defStream);
		CUDA_Check( cudaStreamSynchronize(defStream) );

		cudaDeviceSynchronize();
	}


	HostBuffer<Acceleration> accs(particles.size);








	return 0;
}
