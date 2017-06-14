// Yo ho ho ho
#define private public
#define protected public

#include <core/particle_vector.h>
#include <core/celllist.h>
#include <core/mpi/api.h>
#include <core/logger.h>

#include <core/xml/pugixml.hpp>
#include <core/rigid_object_vector.h>

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

	std::string xml = R"(<node mass="1.0" density="8.0">)";
	pugi::xml_document config;
	config.load_string(xml.c_str());

	float3 length{64,64,64};
	float3 domainStart = -length / 2.0f;
	const float rc = 1.0f;
	ParticleVector dpds("dpd");
	CellList cells(&dpds, rc, length);
	cells.setStream(0);
	cells.makePrimary();

	InitialConditions ic = createIC(config.child("node"));
	ic.exec(MPI_COMM_WORLD, &dpds, {0,0,0}, length);

	const int initialNP = dpds.local()->size();
	HostBuffer<Particle> host(dpds.local()->size());
	const float dt = 0.1;
	for (int i=0; i<dpds.local()->size(); i++)
	{
		dpds.local()->coosvels[i].u.z = 5*(drand48() - 0.5);
		dpds.local()->coosvels[i].u.y = 5*(drand48() - 0.5);
		dpds.local()->coosvels[i].u.z = 5*(drand48() - 0.5);

		dpds.local()->coosvels[i].r += dt * dpds.local()->coosvels[i].u;

		host[i] = dpds.local()->coosvels[i];
	}


	const int nobj = 10;
	PinnedBuffer<RigidObjectVector::RigidMovement> movement(nobj);
	PinnedBuffer<RigidObjectVector::COMandExtent> com_ext(nobj);

	for (int i=0; i<nobj; i++)
	{
		movement[i].omega.x = 2*(drand48() - 0.5);
		movement[i].omega.x = 2*(drand48() - 0.5);
		movement[i].omega.x = 2*(drand48() - 0.5);

		movement[i].vel.x = 2*(drand48() - 0.5);
		movement[i].vel.x = 2*(drand48() - 0.5);
		movement[i].vel.x = 2*(drand48() - 0.5);

		movement[i].force = make_float3(0);
		movement[i].torque = make_float3(0);
}





	for (int i = 0; i<27; i++)
	{
		if (bufs[i].size() != redist.helpers[0]->counts[i])
			printf("%2d-th redist differs in size: %5d, expected %5d\n", i, redist.helpers[0]->counts[i], (int)bufs[i].size());

		std::vector<Particle> got, reference;

		auto cmp = [] (Particle a, Particle b) {
			if (a.i1 < b.i1) return true;
			if (a.i1 > b.i1) return false;

			if (a.r.x > b.r.x + 1e-6) return true;
			if (a.r.y > b.r.y + 1e-6) return true;
			if (a.r.z > b.r.z + 1e-6) return true;

			return false;
		};

		std::sort(bufs[i].begin(), bufs[i].end(), cmp);
		std::sort((Particle*)redist.helpers[0]->sendBufs[i].hostPtr(), ((Particle*)redist.helpers[0]->sendBufs[i].hostPtr()) + redist.helpers[0]->counts[i], cmp);

		std::set_difference(bufs[i].begin(), bufs[i].end(),
				(Particle*)redist.helpers[0]->sendBufs[i].hostPtr(), ((Particle*)redist.helpers[0]->sendBufs[i].hostPtr()) + redist.helpers[0]->counts[i],
				std::inserter(reference, reference.begin()), cmp);

		std::set_difference(
					(Particle*)redist.helpers[0]->sendBufs[i].hostPtr(), ((Particle*)redist.helpers[0]->sendBufs[i].hostPtr()) + redist.helpers[0]->counts[i],
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
