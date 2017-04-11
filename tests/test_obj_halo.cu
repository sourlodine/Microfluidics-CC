// Yo ho ho ho
#define private public

#include <core/object_vector.h>
#include <core/celllist.h>
#include <core/mpi/api.h>
#include <core/logger.h>
#include <core/xml/pugixml.hpp>
#include <core/components.h>

#include <array>

Logger logger;

inline Particle addShift(Particle p, float3 sh)
{
	Particle res = p;
	res.r += sh;

	return res;
}


void makeCells(const Particle* __restrict__ coos, Particle* __restrict__ buffer, int* __restrict__ cellsStartSize, int* __restrict__ cellsSize,
		int np, CellListInfo cinfo)
{
	for (int i=0; i<cinfo.totcells+1; i++)
		cellsSize[i] = 0;

	for (int i=0; i<np; i++)
		cellsSize[ cinfo.getCellId(coos[i].r) ]++;

	cellsStartSize[0] = 0;
	for (int i=1; i<=cinfo.totcells; i++)
		cellsStartSize[i] = cellsSize[i-1] + cellsStartSize[i-1];

	for (int i=0; i<np; i++)
	{
		const int cid = cinfo.getCellId(coos[i].r);
		buffer[cellsStartSize[cid]] = coos[i];
		cellsStartSize[cid]++;
	}

	for (int i=0; i<cinfo.totcells; i++)
		cellsStartSize[i] -= cellsSize[i];
}

int main(int argc, char ** argv)
{
	// Init

	int nranks, rank;
	int ranks[] = {1, 1, 1};
	int periods[] = {1, 1, 1};
	MPI_Comm cartComm;

	MPI_Init(&argc, &argv);
	logger.init(MPI_COMM_WORLD, "objhalo.log", 9);

	MPI_Check( MPI_Comm_size(MPI_COMM_WORLD, &nranks) );
	MPI_Check( MPI_Comm_rank(MPI_COMM_WORLD, &rank) );
	MPI_Check( MPI_Cart_create(MPI_COMM_WORLD, 3, ranks, periods, 0, &cartComm) );

//	std::string xml = R"(<node mass="1.0" density="8.0">)";
//	pugi::xml_document config;
//	config.load_string(xml.c_str());

	float3 length{24, 24, 24};
	float3 domainStart = -length / 2.0f;
	const float rc = 1.0f;


	const int nobj = 100, objsize = 50;
	const float radius = 5;
	ObjectVector objs("obj", objsize, nobj);
	HostBuffer<int> p2obj(objs.size());

	for (int i=0; i<nobj; i++)
	{
		float3 r0 = make_float3(drand48()-0.5, drand48()-0.5, drand48()-0.5) * length;

		for (int j=0; j<objsize; j++)
		{
			float3 r;
			do
			{
				r = make_float3(drand48()-0.5, drand48()-0.5, drand48()-0.5) * make_float3(2*radius);
			}while (dot(r, r) >= radius*radius);

			Particle p;
			p.r = r+r0;
			p.s11 = j;
			p.s12 = i;
			p.s21 = j;

			objs.coosvels[i*objsize + j] = p;
			p2obj[i*objsize + j] = i*objsize + j;
		}
	}

	objs.domainSize = length;
	objs.coosvels.uploadToDevice();
	objs.particles2objIds.copy(p2obj);

	CellList cells(&objs, rc, length + make_float3(radius));

	objs.findExtentAndCOM(0);
	cells.build(0);

	objs.coosvels.downloadFromDevice(true);

	cudaStream_t defStream = 0;

	HaloExchanger halo(cartComm, 0);
	halo.attach(&objs, rc);

	cells.build(defStream);
	CUDA_Check( cudaStreamSynchronize(defStream) );

	for (int i=0; i<1; i++)
	{
		halo.init();
		halo.finalize();
	}

	std::vector<Particle> bufs[27];
	objs.coosvels.downloadFromDevice(true);
	objs.halo.downloadFromDevice(true);
	p2obj.copy(objs.particles2objIds, 0);

	// =================================================================================================================

//	std::vector<Particle> tmp(objs.np);
//	std::vector<int> cellsStartSize(cells.totcells+1), cellsSize(cells.totcells);
//
//	makeCells(objs.coosvels.hostPtr(), tmp.data(), cellsStartSize.data(), cellsSize.data(), objs.np, cells.cellInfo());
//
//	for (int i=0; i<cells.totcells; i++)
//	{
//		if (cellsSize[i] > 100) printf("%d => %d\n", i, cellsSize[i]);
//	}

	// =================================================================================================================

	HostBuffer<ObjectVector::COMandExtent> props;
	props.copy(objs.com_extent, defStream);
	for (int i=0; i<objs.nObjects; i++)
		printf("%3d:  [%8.3f %8.3f %8.3f] -- [%8.3f %8.3f %8.3f]\n", i,
				props[i].low.x, props[i].low.y, props[i].low.z, props[i].high.x, props[i].high.y, props[i].high.z);

	std::vector<std::array<bool, 27>> haloObj(objs.nObjects);
	CellListInfo tightCells(1.0f, length);
	for (int i=0; i<objs.np; i++)
	{
		Particle& p = objs.coosvels[i];

		int3 code = tightCells.getCellIdAlongAxis(p.r);
		int cx = code.x,  cy = code.y,  cz = code.z;
		auto ncells = tightCells.ncells;

		if (p.s12 == 73)
			printf("%d:  [%f %f %f] => [%d %d %d]\n", p.s11, p.r.x, p.r.y, p.r.z, cx, cy, cz);

		std::vector<std::pair<int, float3>> bufShift;
		// 6
		if (cx == 0)          bufShift.push_back({ (1*3 + 1)*3 + 0, make_float3( length.x,         0,         0) });
		if (cx == ncells.x-1) bufShift.push_back({ (1*3 + 1)*3 + 2, make_float3(-length.x,         0,         0) });
		if (cy == 0)          bufShift.push_back({ (1*3 + 0)*3 + 1, make_float3(        0,  length.y,         0) });
		if (cy == ncells.y-1) bufShift.push_back({ (1*3 + 2)*3 + 1, make_float3(        0, -length.y,         0) });
		if (cz == 0)          bufShift.push_back({ (0*3 + 1)*3 + 1, make_float3(        0,         0,  length.z) });
		if (cz == ncells.z-1) bufShift.push_back({ (2*3 + 1)*3 + 1, make_float3(        0,         0, -length.z) });

		// 12
		if (cx == 0          && cy == 0)          bufShift.push_back({ (1*3 + 0)*3 + 0, make_float3( length.x,  length.y,         0) });
		if (cx == ncells.x-1 && cy == 0)          bufShift.push_back({ (1*3 + 0)*3 + 2, make_float3(-length.x,  length.y,         0) });
		if (cx == 0          && cy == ncells.y-1) bufShift.push_back({ (1*3 + 2)*3 + 0, make_float3( length.x, -length.y,         0) });
		if (cx == ncells.x-1 && cy == ncells.y-1) bufShift.push_back({ (1*3 + 2)*3 + 2, make_float3(-length.x, -length.y,         0) });

		if (cy == 0          && cz == 0)          bufShift.push_back({ (0*3 + 0)*3 + 1, make_float3(        0,  length.y,  length.z) });
		if (cy == ncells.y-1 && cz == 0)          bufShift.push_back({ (0*3 + 2)*3 + 1, make_float3(        0, -length.y,  length.z) });
		if (cy == 0          && cz == ncells.z-1) bufShift.push_back({ (2*3 + 0)*3 + 1, make_float3(        0,  length.y, -length.z) });
		if (cy == ncells.y-1 && cz == ncells.z-1) bufShift.push_back({ (2*3 + 2)*3 + 1, make_float3(        0, -length.y, -length.z) });


		if (cz == 0          && cx == 0)          bufShift.push_back({ (0*3 + 1)*3 + 0, make_float3( length.x,         0,  length.z) });
		if (cz == ncells.z-1 && cx == 0)          bufShift.push_back({ (2*3 + 1)*3 + 0, make_float3( length.x,         0, -length.z) });
		if (cz == 0          && cx == ncells.x-1) bufShift.push_back({ (0*3 + 1)*3 + 2, make_float3(-length.x,         0,  length.z) });
		if (cz == ncells.z-1 && cx == ncells.x-1) bufShift.push_back({ (2*3 + 1)*3 + 2, make_float3(-length.x,         0, -length.z) });

		// 8
		if (cx == 0          && cy == 0          && cz == 0)          bufShift.push_back({ (0*3 + 0)*3 + 0, make_float3( length.x,  length.y,  length.z) });
		if (cx == 0          && cy == 0          && cz == ncells.z-1) bufShift.push_back({ (2*3 + 0)*3 + 0, make_float3( length.x,  length.y, -length.z) });
		if (cx == 0          && cy == ncells.y-1 && cz == 0)          bufShift.push_back({ (0*3 + 2)*3 + 0, make_float3( length.x, -length.y,  length.z) });
		if (cx == 0          && cy == ncells.y-1 && cz == ncells.z-1) bufShift.push_back({ (2*3 + 2)*3 + 0, make_float3( length.x, -length.y, -length.z) });
		if (cx == ncells.x-1 && cy == 0          && cz == 0)          bufShift.push_back({ (0*3 + 0)*3 + 2, make_float3(-length.x,  length.y,  length.z) });
		if (cx == ncells.x-1 && cy == 0          && cz == ncells.z-1) bufShift.push_back({ (2*3 + 0)*3 + 2, make_float3(-length.x,  length.y, -length.z) });
		if (cx == ncells.x-1 && cy == ncells.y-1 && cz == 0)          bufShift.push_back({ (0*3 + 2)*3 + 2, make_float3(-length.x, -length.y,  length.z) });
		if (cx == ncells.x-1 && cy == ncells.y-1 && cz == ncells.z-1) bufShift.push_back({ (2*3 + 2)*3 + 2, make_float3(-length.x, -length.y, -length.z) });

		for (auto& entry : bufShift)
		{
			int objId = p.s12;
			if (haloObj[objId][entry.first] == false)
			{
				for (int i=0; i<objsize; i++)
				{
					const int pid = p2obj[objId*objsize + i];
					bufs[entry.first].push_back(addShift(objs.coosvels[pid], entry.second));
				}
				haloObj[objId][entry.first] = true;
			}
		}
	}

	for (int i = 0; i<27; i++)
	{
		auto ptr = (Particle*)halo.objectHelpers[0]->sendBufs[i].hostPtr();

		std::sort(bufs[i].begin(), bufs[i].end(),				[] (Particle& a, Particle& b) { return a.i1 < b.i1; });
		std::sort(ptr, ptr + halo.objectHelpers[0]->counts[i],  [] (Particle& a, Particle& b) { return a.i1 < b.i1; });

		if (bufs[i].size() != halo.objectHelpers[0]->counts[i])
		{
			printf("%2d-th halo differs in size: %5d, expected %5d\n", i, halo.objectHelpers[0]->counts[i], (int)bufs[i].size());

			printf("  Got:  ");
			for (int j=0; j<halo.objectHelpers[0]->counts[i] / objs.objSize; j++)
				printf("%2d ", ptr[j*objs.objSize].s12);
			printf("\n");

			printf("  Exp:  ");
			for (int j=0; j<bufs[i].size() / objs.objSize; j++)
				printf("%2d ", bufs[i][j*objs.objSize].s12);
			printf("\n\n");
		}
		else
		{
			for (int pid = 0; pid < min(halo.objectHelpers[0]->counts[i], (int)bufs[i].size()); pid++)
			{
				const float diff = std::max({
					fabs(ptr[pid].r.x - bufs[i][pid].r.x),
					fabs(ptr[pid].r.y - bufs[i][pid].r.y),
					fabs(ptr[pid].r.z - bufs[i][pid].r.z) });

				if (bufs[i][pid].i1 != ptr[pid].i1 || diff > 1e-5)
					printf("Halo %2d:  %3d obj %3d [%8.3f %8.3f %8.3f], expected %3d obj %3d [%8.3f %8.3f %8.3f]\n",
							i, ptr[pid].s11, ptr[pid].s12, ptr[pid].r.x, ptr[pid].r.y, ptr[pid].r.z,
							bufs[i][pid].s11, bufs[i][pid].s12, bufs[i][pid].r.x, bufs[i][pid].r.y, bufs[i][pid].r.z);
			}
		}
	}

//	for (int i=0; i<objs.halo.size(); i++)
//		printf("%d  %f %f %f\n", i, objs.halo[i].r.x, objs.halo[i].r.y, objs.halo[i].r.z);

	return 0;
}
