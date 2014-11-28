#pragma once

#include <mpi.h>

#include "common.h"

class HaloExchanger
{
    MPI_Comm cartcomm;
    MPI_Request sendreq[26], recvreq[26], sendcellsreq[26], recvcellsreq[26];
    
    //mpi send and recv informations
    int recv_tags[26], nlocal;
    SimpleDeviceBuffer<int> tmpstart[26], tmpcount[26];

protected:

    int L, myrank, nranks, dims[3], periods[3], coords[3], dstranks[26];
    
    //zero-copy allocation for acquiring the message offsets in the gpu send buffer
    int * required_send_bag_size, * required_send_bag_size_host;
        
    //plain copy of the offsets for the cpu (i speculate that reading multiple times the zero-copy entries is slower)
    int nsendreq, nrecvreq;

    SimpleDeviceBuffer<Particle> sendbufs[26], recvbufs[26];  
    SimpleDeviceBuffer<int> scattered_entries[26], sendcellstarts[26], recvcellstarts[26];
    int3 halosize[26];
    //cuda-sync after to wait for packing of the halo, mpi non-blocking
    void pack_and_post(const Particle * const p, const int n, const int * const cellsstart, const int * const cellscount);

    //mpi-sync for the surrounding halos, shift particle coord to the sysref of this rank
    void wait_for_messages();
    
    int nof_sent_particles();
    
public:
    
    HaloExchanger(MPI_Comm cartcomm, int L);
    
    ~HaloExchanger();

    SimpleDeviceBuffer<Particle> exchange(const Particle * const plocal, int nlocal, const int * const cellsstart, const int * const cellscount);
};
