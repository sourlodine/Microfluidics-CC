#pragma once

#include <mpi.h>

#include <rbc-cuda.h>

#include "common.h"

class RedistributeRBCs
{
protected:

    MPI_Comm cartcomm;
    std::vector<MPI_Request> sendreq, recvreq;
    
    int myrank, dims[3], periods[3], coords[3], rankneighbors[27], anti_rankneighbors[27];

    PinnedHostBuffer /*SimpleDeviceBuffer*/<Particle> recvbufs[27], sendbufs[27];

    int nvertices, arriving, notleaving;

    cudaEvent_t evextents;

    PinnedHostBuffer<CudaRBC::Extent> extents;

    virtual void _compute_extents(const Particle * const xyzuvw, const int nrbcs, cudaStream_t stream);
    
public:
    
    RedistributeRBCs(MPI_Comm comm);
        
    int stage1(const Particle * const xyzuvw, const int nrbcs, cudaStream_t stream);
    
    void stage2(Particle * const xyzuvw, const int nrbcs, cudaStream_t stream);

    ~RedistributeRBCs();
};
