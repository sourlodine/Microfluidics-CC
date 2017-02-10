#pragma once

#include <mpi.h>
#include <string>
#include <core/logger.h>
#include <core/datatypes.h>

class Simulation;

class SimulationPlugin
{
public:
	std::string name;

protected:
	Simulation* sim;
	MPI_Comm comm;
	MPI_Comm interComm;
	int rank;
	MPI_Request req;
	cudaStream_t stream;
	float tm;

	int id;

	void send(const void* data, int sizeInBytes)
	{
		MPI_Check( MPI_Wait(&req, MPI_STATUS_IGNORE) );
		MPI_Check( MPI_Isend(data, sizeInBytes, MPI_BYTE, rank, id, interComm, &req) );
	}

public:
	SimulationPlugin(std::string name) : name(name), req(MPI_REQUEST_NULL) {};

	virtual void beforeForces(float t) {};
	virtual void beforeIntegration(float t) {};
	virtual void afterIntegration(float t) {};

	virtual void serializeAndSend() {};
	virtual void handshake() {};
	virtual void talk() {};

	void setup(Simulation* sim, cudaStream_t stream, const MPI_Comm& comm, const MPI_Comm& interComm)
	{
		this->sim       = sim;
		this->stream    = stream;

		MPI_Check( MPI_Comm_dup(comm,      &this->comm) );
		MPI_Check( MPI_Comm_dup(interComm, &this->interComm) );

		MPI_Check( MPI_Comm_rank(this->comm, &rank) );
	}
	void setId(int id) { this->id = id; }

	virtual ~SimulationPlugin() {};
};

class PostprocessPlugin
{
public:
	std::string name;

protected:
	MPI_Comm comm, interComm;
	int rank;
	HostBuffer<char> data;
	int size;

	int id;

public:
	PostprocessPlugin(std::string name) : name(name) { }

	MPI_Request postRecv()
	{
		MPI_Request req;
		MPI_Check( MPI_Irecv(data.hostPtr(), size, MPI_BYTE, rank, id, interComm, &req) );
		return req;
	}

	virtual void deserialize(MPI_Status& stat) {};
	virtual void handshake() {};
	virtual void talk() {};

	void setup(const MPI_Comm& comm, const MPI_Comm& interComm)
	{
		MPI_Check( MPI_Comm_dup(comm,      &this->comm) );
		MPI_Check( MPI_Comm_dup(interComm, &this->interComm) );

		MPI_Check( MPI_Comm_rank(this->comm, &rank) );
	}
	void setId(int id) { this->id = id; }

	virtual ~PostprocessPlugin() {};
};





