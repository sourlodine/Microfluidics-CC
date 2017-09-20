#include "udevicex.h"

#include <mpi.h>
#include <core/logger.h>
#include <core/simulation.h>
#include <core/postproc.h>
#include <plugins/interface.h>

uDeviceX::uDeviceX(int3 nranks3D, float3 globalDomainSize,
		Logger& logger, std::string logFileName, int verbosity, bool noPostprocess) : noPostprocess(noPostprocess)
{
	int nranks, rank;

	if (logFileName == "stdout")
		logger.init(MPI_COMM_WORLD, stdout, verbosity);
	else if (logFileName == "stderr")
		logger.init(MPI_COMM_WORLD, stderr, verbosity);
	else
		logger.init(MPI_COMM_WORLD, logFileName+".log", verbosity);

	MPI_Check( MPI_Comm_size(MPI_COMM_WORLD, &nranks) );
	MPI_Check( MPI_Comm_rank(MPI_COMM_WORLD, &rank) );

	if (rank == 0)
		sayHello();

	MPI_Comm ioComm, compComm, interComm, splitComm;

	if (noPostprocess)
	{
		warn("No postprocess will be started now, use this mode for debugging. All the joint plugins will be turned off too.");

		sim = new Simulation(nranks3D, globalDomainSize, MPI_COMM_WORLD, MPI_COMM_NULL);
		computeTask = 0;
		return;
	}

	if (nranks % 2 != 0)
		die("Number of MPI ranks should be even");

	info("Program started, splitting communicator");

	computeTask = (rank) % 2;
	MPI_Check( MPI_Comm_split(MPI_COMM_WORLD, computeTask, rank, &splitComm) );

	if (isComputeTask())
	{
		MPI_Check( MPI_Comm_dup(splitComm, &compComm) );
		MPI_Check( MPI_Intercomm_create(compComm, 0, MPI_COMM_WORLD, 1, 0, &interComm) );

		MPI_Check( MPI_Comm_rank(compComm, &rank) );

		sim = new Simulation(nranks3D, globalDomainSize, compComm, interComm);
	}
	else
	{
		MPI_Check( MPI_Comm_dup(splitComm, &ioComm) );
		MPI_Check( MPI_Intercomm_create(ioComm,   0, MPI_COMM_WORLD, 0, 0, &interComm) );

		MPI_Check( MPI_Comm_rank(ioComm, &rank) );

		post = new Postprocess(ioComm, interComm);
	}
}

void uDeviceX::sayHello()
{
	printf("\n");
	printf("************************************************\n");
	printf("*                   uDeviceX                   *\n");
	printf("*     compiled: on %s at %s     *\n", __DATE__, __TIME__);
	printf("************************************************\n");
	printf("\n");
}

bool uDeviceX::isComputeTask()
{
	return computeTask == 0;
}

void uDeviceX::registerJointPlugins(SimulationPlugin* simPl, PostprocessPlugin* postPl)
{
	if (noPostprocess) return;

	const int id = pluginId++;

	if (isComputeTask())
	{
		simPl->setId(id);
		sim->registerPlugin(simPl);
	}
	else
	{
		postPl->setId(id);
		post->registerPlugin(postPl);
	}
}

void uDeviceX::run(int nsteps)
{
	if (isComputeTask())
	{
		sim->init();
		sim->run(nsteps);
		sim->finalize();

		CUDA_Check( cudaDeviceSynchronize() );
	}
	else
		post->run();

	MPI_Finalize();
}

