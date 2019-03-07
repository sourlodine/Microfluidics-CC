#pragma once

#include "fetchers.h"

#include <core/interactions/accumulators/density.h>
#include <core/ymero_state.h>

class CellList;
class LocalParticleVector;

class PairwiseDensity : public ParticleFetcher
{
public:

    using ViewType     = PVviewWithDensities;
    using ParticleType = Particle;
    using HandlerType = PairwiseDensity;
    
    PairwiseDensity(float rc) :
        ParticleFetcher(rc)
    {
        invrc = 1.0 / rc;
        fact = 15.0 / (2 * M_PI * rc2 * rc);
    }

    __D__ inline float operator()(const ParticleType dst, int dstId, const ParticleType src, int srcId) const
    {
        float3 dr = dst.r - src.r;
        float rij2 = dot(dr, dr);
        if (rij2 > rc2) return 0.0f;

        float rij = sqrtf(rij2);
        float argwr = 1.0f - rij * invrc;

        return fact * argwr * argwr;
    }

    __D__ inline DensityAccumulator getZeroedAccumulator() const {return DensityAccumulator();}


    const HandlerType& handler() const
    {
        return (const HandlerType&) (*this);
    }
    
    void setup(LocalParticleVector *lpv1, LocalParticleVector *lpv2, CellList *cl1, CellList *cl2, const YmrState *state)
    {}   

protected:

    float invrc, fact;
};
