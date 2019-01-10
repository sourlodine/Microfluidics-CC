#include "simple_stationary_wall.h"

#pragma once

#include "interface.h"

#include <core/containers.h>

class ParticleVector;
class CellList;


template<class InsideWallChecker, class VelocityField>
class WallWithVelocity : public SimpleStationaryWall<InsideWallChecker>
{
public:
    WallWithVelocity(std::string name, const YmrState *state, InsideWallChecker&& insideWallChecker, VelocityField&& velField) :
        SimpleStationaryWall<InsideWallChecker>(name, state, std::move(insideWallChecker)),
        velField(std::move(velField))
    {}

    void setup(MPI_Comm& comm, float t, DomainInfo domain) override;
    void attachFrozen(ParticleVector* pv) override;

    void bounce(cudaStream_t stream) override;

protected:
    VelocityField velField;
    DomainInfo domain;
};
