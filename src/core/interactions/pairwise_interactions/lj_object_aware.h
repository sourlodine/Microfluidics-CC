#pragma once

#include <core/datatypes.h>
#include <core/interactions/accumulators/force.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/particle_vector.h>
#include <core/utils/cpu_gpu_defines.h>
#include <core/utils/helper_math.h>

class Pairwise_LJObjectAware
{
public:

    using ViewType     = PVview;
    using ParticleType = Particle;
    
    Pairwise_LJObjectAware(float rc, float epsilon, float sigma, float maxForce) :
        lj(rc, epsilon, sigma, maxForce)
    {}

    void setup(LocalParticleVector* lpv1, LocalParticleVector* lpv2, CellList* cl1, CellList* cl2, float t)
    {
        auto ov1 = dynamic_cast<ObjectVector*>(lpv1->pv);
        auto ov2 = dynamic_cast<ObjectVector*>(lpv2->pv);

        self = false;
        if (ov1 != nullptr && ov2 != nullptr && lpv1 == lpv2)
        {
            self = true;
            objSize = ov1->objSize;
        }
    }

    __D__ inline ParticleType read(const ViewType& view, int id) const                     { return        lj.read(view, id); }
    __D__ inline ParticleType readNoCache(const ViewType& view, int id) const              { return lj.readNoCache(view, id); }
    __D__ inline void readCoordinates(ParticleType& p, const ViewType& view, int id) const { lj.readCoordinates(p, view, id); }
    __D__ inline void readExtraData  (ParticleType& p, const ViewType& view, int id) const { lj.readExtraData  (p, view, id); }

    __D__ inline bool withinCutoff(const ParticleType& src, const ParticleType& dst) const { return lj.withinCutoff(src, dst); }
    __D__ inline float3 getPosition(const ParticleType& p) const {return lj.getPosition(p);}

    __D__ inline float3 operator()(ParticleType dst, int dstId, ParticleType src, int srcId) const
    {
        if (self)
        {
            const int dstObjId = dst.i1 / objSize;
            const int srcObjId = src.i1 / objSize;

            if (dstObjId == srcObjId) return make_float3(0.0f);
        }

        float3 f = lj(dst, dstId, src, srcId);

        return f;
    }

    __D__ inline ForceAccumulator getZeroedAccumulator() const {return ForceAccumulator();}

private:

    bool self;

    int objSize;

    Pairwise_LJ lj;
};
