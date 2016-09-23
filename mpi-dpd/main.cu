/*
 *  main.cu
 *  Part of uDeviceX/mpi-dpd/
 *
 *  Created and authored by Diego Rossinelli on 2014-11-14.
 *  Copyright 2015. All rights reserved.
 *
 *  Users are NOT authorized
 *  to employ the present software for their own publications
 *  before getting a written permission from the author of this file.
 */

#include <cstdio>
#include <cassert>
#include <csignal>
#include <mpi.h>
#include <errno.h>
#if defined(REPORT_TOPOLOGY)
#include <pmi.h>
#endif

#include "argument-parser.h"
#include "simulation.h"
#include "dumper.h"

bool currently_profiling = false;
float tend, couette;
bool walls, pushtheflow, doublepoiseuille, rbcs, ctcs, xyz_dumps, hdf5field_dumps,
hdf5part_dumps, is_mps_enabled, adjust_message_sizes, contactforces, stress;
int steps_per_report, steps_per_dump, wall_creation_stepid, nvtxstart, nvtxstop, nsubsteps;

LocalComm localcomm;

namespace SignalHandling
{
	volatile sig_atomic_t gracefulExit = 0;

	void signalHandler(int signum)
	{
		gracefulExit = 1;
	}

	void setup()
	{
		struct sigaction action;
		memset(&action, 0, sizeof(struct sigaction));
		action.sa_handler = signalHandler;
		sigaction(SIGUSR1, &action, NULL);
		sigaction(SIGTERM, &action, NULL);
	}

	bool checkTerminationRequest()
	{
		return gracefulExit;
	}
}

int main(int argc, char ** argv)
{
	int ranks[3];

	//parsing of the positional arguments
	if (argc < 4)
	{
		printf("usage: ./mpi-dpd <xranks> <yranks> <zranks>\n");
		exit(-1);
	}
	else
		for(int i = 0; i < 3; ++i)
			ranks[i] = atoi(argv[1 + i]);

	ArgumentParser argp(vector<string>(argv + 4, argv + argc));

	tend = argp("-tend").asDouble(50);
	walls = argp("-walls").asBool(false);
	pushtheflow = argp("-pushtheflow").asBool(false);
	doublepoiseuille = argp("-doublepoiseuille").asBool(false);
	rbcs = argp("-rbcs").asBool(false);
	ctcs = argp("-ctcs").asBool(false);
	xyz_dumps = argp("-xyz_dumps").asBool(false);
	hdf5field_dumps = argp("-hdf5field_dumps").asBool(false);
	steps_per_report = argp("-steps_per_report").asInt(1000);
	steps_per_dump = argp("-steps_per_dump").asInt(1000);
	wall_creation_stepid = argp("-wall_creation_stepid").asInt(5000);
	nvtxstart = argp("-nvtxstart").asInt(10400);
	nvtxstop = argp("-nvtxstop").asInt(10500);
	adjust_message_sizes = argp("-adjust_message_sizes").asBool(false);
	contactforces = argp("-contactforces").asBool(false);
	stress = argp("-stress").asBool(false);
	couette = argp("-couette").asDouble(0);
	nsubsteps = argp("-nsubsteps").asInt(0);

	SignalHandling::setup();

#ifdef _USE_NVTX_
	nvtxNameOsThread(pthread_self(), "MASTER_THREAD");
#endif

	CUDA_CHECK(cudaSetDevice(0));

	CUDA_CHECK(cudaDeviceReset());

	{
		is_mps_enabled = false;

		const char * mps_variables[] = {
				"CRAY_CUDA_MPS",
				"CUDA_MPS",
				"CRAY_CUDA_PROXY",
				"CUDA_PROXY"
		};

		for(int i = 0; i < 4; ++i)
			is_mps_enabled |= getenv(mps_variables[i])!= NULL && atoi(getenv(mps_variables[i])) != 0;
	}

	int nranks, rank;


	MPI_CHECK(MPI_Init(&argc, &argv));
	MPI_CHECK( MPI_Comm_size(MPI_COMM_WORLD, &nranks) );
	MPI_CHECK( MPI_Comm_rank(MPI_COMM_WORLD, &rank) );

	MPI_Comm  iocomm, activecomm, intercomm, splitcomm;

	assert(nranks & 0x1 == 0);
	int computeTask = (rank+1) % 2;
	MPI_CHECK( MPI_Comm_split(MPI_COMM_WORLD, computeTask, rank, &splitcomm) );
	if (computeTask)
		MPI_CHECK( MPI_Comm_dup(splitcomm, &activecomm) );
	else
		MPI_CHECK( MPI_Comm_dup(splitcomm, &iocomm) );

	if (computeTask)
		MPI_CHECK( MPI_Intercomm_create(activecomm, 0, MPI_COMM_WORLD, 1, 0, &intercomm) );
	else
		MPI_CHECK( MPI_Intercomm_create(iocomm,     0, MPI_COMM_WORLD, 0, 0, &intercomm) );


#if defined(CUSTOM_REORDERING)
    		activecomm = setup_reorder_comm(MPI_COMM_WORLD, rank, nranks);
#endif

    		bool reordering = true;

    		const char * env_reorder = getenv("MPICH_RANK_REORDER_METHOD");

    		//reordering of the ranks according to the computational domain and environment variables
    		if (computeTask && atoi(env_reorder ? env_reorder : "-1") == atoi("3"))
    		{
    			reordering = false;

    			const bool usefulrank = rank < ranks[0] * ranks[1] * ranks[2];

    			MPI_CHECK(MPI_Comm_split(MPI_COMM_WORLD, usefulrank, rank, &activecomm)) ;

    			MPI_CHECK(MPI_Barrier(activecomm));

    			if (!usefulrank)
    			{
    				printf("rank %d has been thrown away\n", rank);
    				fflush(stdout);

    				MPI_CHECK(MPI_Barrier(activecomm));

    				MPI_Finalize();

    				return 0;
    			}

    			MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
    		}

    		MPI_Comm cartcomm, iocartcomm;

    		int periods[] = {1, 1, 1};

    		if (computeTask)
    			MPI_CHECK( MPI_Cart_create(activecomm, 3, ranks, periods, (int)reordering, &cartcomm) );
    		else
    			MPI_CHECK( MPI_Cart_create(iocomm, 3, ranks, periods, (int)reordering, &iocartcomm) );

    		activecomm = cartcomm;

    		//print the rank-to-node mapping
    		if (computeTask)
    		{
    			char name[1024];
    			int len;
    			MPI_CHECK(MPI_Get_processor_name(name, &len));

    			int dims[3], periods[3], coords[3];
    			MPI_CHECK( MPI_Cart_get(cartcomm, 3, dims, periods, coords) );

    			MPI_CHECK(MPI_Barrier(activecomm));
#if defined(REPORT_TOPOLOGY)
    			int nid;
    			int rc = PMI_Get_nid(rank, &nid);
    			pmi_mesh_coord_t xyz;
    			PMI_Get_meshcoord((uint16_t) nid, &xyz);
    			printf("RANK %d: (%d, %d, %d) -> %s (%d, %d, %d)\n", rank, coords[0], coords[1], coords[2], name, xyz.mesh_x, xyz.mesh_y, xyz.mesh_z);
#else
    			printf("RANK %d: (%d, %d, %d) -> %s\n", rank, coords[0], coords[1], coords[2], name);
#endif
    			fflush(stdout);

    			MPI_CHECK(MPI_Barrier(activecomm));
    		}

    		//RAII
    		{
    			if (computeTask)
    			{
    				MPI_CHECK(MPI_Barrier(activecomm));

    				if (rank == 0)
    				{
    					argp.print_arguments();
    					fflush(stdout);
    				}

    				localcomm.initialize(activecomm);

    				MPI_CHECK(MPI_Barrier(activecomm));

    				Simulation simulation(cartcomm, activecomm, intercomm, SignalHandling::checkTerminationRequest);
    				simulation.run();
    			}
    			else
    			{
    				Dumper dumper(iocomm, iocartcomm, intercomm);
    				dumper.do_dump();
    			}
    		}

    		if (computeTask)
    		{
    			if (activecomm != cartcomm)
    				MPI_CHECK(MPI_Comm_free(&activecomm));

    			MPI_CHECK(MPI_Comm_free(&cartcomm));
    			MPI_CHECK(MPI_Comm_free(&intercomm));
    		}
    		else
    		{
    			MPI_CHECK(MPI_Comm_free(&iocomm));
    			MPI_CHECK(MPI_Comm_free(&intercomm));
    		}

    		MPI_CHECK(MPI_Finalize());

    		if (computeTask)
    		{
    			CUDA_CHECK(cudaDeviceSynchronize());

    			CUDA_CHECK(cudaDeviceReset());
    		}

    		return 0;
}
