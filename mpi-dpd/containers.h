/*
 *  containers.h
 *  Part of CTC/mpi-dpd/
 *
 *  Created and authored by Diego Rossinelli on 2014-12-05.
 *  Copyright 2015. All rights reserved.
 *
 *  Users are NOT authorized
 *  to employ the present software for their own publications
 *  before getting a written permission from the author of this file.
 */

#pragma once

#include <vector>
#include <string>

#include "common.h"

struct ParticleArray
{
    int size;

    SimpleDeviceBuffer<Particle> xyzuvw;
    SimpleDeviceBuffer<Acceleration> axayaz;

    ParticleArray() {}
    
    ParticleArray(std::vector<Particle> ic);

    void resize(int n);
    void update_stage1(const float driving_acceleration, cudaStream_t stream);
    void update_stage2_and_1(const float driving_acceleration, cudaStream_t stream);
    void clear_velocity();
};

class CollectionRBC : public ParticleArray
{
protected:
    MPI_Comm cartcomm;
    
    int nrbcs, myrank, dims[3], periods[3], coords[3];
    
    std::string path2xyz, format4ply, path2ic;

    virtual void _initialize(float *device_xyzuvw, const float (*transform)[4]);
    
    int (*indices)[3];
    int ntriangles;

public:
    
    int nvertices, dumpcounter;

    CollectionRBC(MPI_Comm cartcomm, const std::string path2ic = "rbcs-ic.txt");

    void setup();
     
    Particle * data() { return xyzuvw.data; }
    Acceleration * acc() { return axayaz.data; }
    void remove(const int * const entries, const int nentries);
    void resize(const int rbcs_count);
    
    int count() { return nrbcs; }
    int pcount() { return nrbcs * nvertices; }
    
    void dump(MPI_Comm comm, MPI_Comm cartcomm);
};

