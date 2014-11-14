#pragma once

#include <mpi.h>

#include "common.h"

/* particles may fall outside my subdomain. i might loose old particles and receive new ones.
   redistribution is performed in 2 stages and unfortunately the first stage is stateful (because of tmp vector here below)
   that's why i need a class. */
class RedistributeParticles
{
    MPI_Comm cartcomm;

    bool pending_send;
    
    int L, myrank, dims[3], periods[3], coords[3], rankneighbors[27], domain_extent[3];
    int * leaving_start, *leaving_start_device, arriving_start[28], notleaving, arriving;

    //in the non-vanilla version this will be a device vector
    //std::vector<Particle> tmp;
    Particle * tmp;
    int tmp_size;

    MPI_Request sendreq[27], recvreq[27];
    
public:

    //initalizes most of the data members of the class
    RedistributeParticles(MPI_Comm cartcomm, int L);

    //performs non-blocking mpi sends of particle packs no longer belonging to my subdomain
    //it involves a reordering of the particles by using 27 bins
    int stage1(Particle * p, int n);

    //waits for the mpi (containings packs of new particles) messages to arrive
    void stage2(Particle * p, int n);
};

