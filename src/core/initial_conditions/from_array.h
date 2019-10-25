#pragma once

#include "interface.h"

#include <vector_types.h>
#include <vector>

class FromArrayIC : public InitialConditions
{
public:
    FromArrayIC(const std::vector<real3>& pos, const std::vector<real3>& vel);

    void exec(const MPI_Comm& comm, ParticleVector *pv, cudaStream_t stream) override;

private:
    std::vector<real3> pos, vel;
};

