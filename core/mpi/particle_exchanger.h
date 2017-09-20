#pragma once

#include <core/containers.h>

#include <vector>
#include <string>

struct ExchangeHelper
{
	int datumSize;

	std::string name;

	PinnedBuffer<int>   bufSizes;
	PinnedBuffer<char>  sendBufs[27];
	PinnedBuffer<char*> sendAddrs;
	PinnedBuffer<char>  recvBufs[27];
	PinnedBuffer<char*> recvAddrs;

	std::vector<int> recvOffsets;
	std::vector<MPI_Request> requests;

	ExchangeHelper(std::string name, const int datumSize, const int sizes[3]);
};

class ParticleExchanger
{
protected:
	int dir2rank[27];
	int compactedDirs[27];
	int nActiveNeighbours;

	int myrank;
	MPI_Comm haloComm;

	std::vector<ExchangeHelper*> helpers;

	void postRecv(ExchangeHelper* helper);
	void sendWait(ExchangeHelper* helper, cudaStream_t stream);

	virtual void prepareData(int id, cudaStream_t stream) = 0;
	virtual void combineAndUploadData(int id, cudaStream_t stream) = 0;

public:

	ParticleExchanger(MPI_Comm& comm);
	void init(cudaStream_t stream);
	void finalize(cudaStream_t stream);

	virtual ~ParticleExchanger() = default;
};
