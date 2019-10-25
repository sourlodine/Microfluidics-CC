#pragma once

#include <core/domain.h>
#include <core/datatypes.h>

#include <core/utils/cpu_gpu_defines.h>
#include <core/utils/helper_math.h>

class ParticleVector;

class StationaryWall_Plane
{
public:
    StationaryWall_Plane(real3 normal, real3 pointThrough) :
        normal(normal), pointThrough(pointThrough)
    {
        normal = normalize(normal);
    }

    void setup(__UNUSED MPI_Comm& comm, DomainInfo domain) { this->domain = domain; }

    const StationaryWall_Plane& handler() const { return *this; }

    __D__ inline real operator()(real3 coo) const
    {
        real3 gr = domain.local2global(coo);
        real dist = dot(normal, gr - pointThrough);

        return dist;
    }

private:
    real3 normal, pointThrough;

    DomainInfo domain;
};
