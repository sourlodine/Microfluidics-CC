#pragma once

#include "interface.h"

/**
 * Implements bounce-back from the analytical ellipsoid shapes
 */
class BounceFromRigidEllipsoid : public Bouncer
{
public:

    BounceFromRigidEllipsoid(std::string name, const YmrState *state);
    ~BounceFromRigidEllipsoid();

    void setup(ObjectVector* ov) override;

protected:

    void exec(ParticleVector* pv, CellList* cl, float dt, bool local, cudaStream_t stream) override;
};
