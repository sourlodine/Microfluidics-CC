#pragma once

#include "accumulators/force.h"
#include "fetchers.h"
#include "interface.h"
#include "parameters.h"

#include <mirheo/core/mirheo_state.h>
#include <mirheo/core/pvs/object_vector.h>
#include <mirheo/core/pvs/rod_vector.h>

namespace mirheo
{

class LJAwarenessNone
{
public:
    using ParamsType = LJAwarenessParamsNone;
    
    LJAwarenessNone() = default;
    LJAwarenessNone(__UNUSED const ParamsType& params) {}
    
    void setup(__UNUSED LocalParticleVector *lpv1, __UNUSED LocalParticleVector *lpv2) {}
    __D__ inline bool interact(__UNUSED int srcId, __UNUSED int dstId) const {return true;}
};
MIRHEO_TYPE_NAME(LJAwarenessNone, "LJAwarenessNone");

class LJAwarenessObject
{
public:
    using ParamsType = LJAwarenessParamsObject;
    
    LJAwarenessObject() = default;
    LJAwarenessObject(__UNUSED const ParamsType& params) {}
    
    void setup(LocalParticleVector *lpv1, LocalParticleVector *lpv2)
    {
        auto ov1 = dynamic_cast<ObjectVector*>(lpv1->parent());
        auto ov2 = dynamic_cast<ObjectVector*>(lpv2->parent());

        self_ = false;
        if (ov1 != nullptr && ov2 != nullptr && lpv1 == lpv2)
        {
            self_ = true;
            objSize_ = ov1->getObjectSize();
        }
    }

    __D__ inline bool interact(int srcId, int dstId) const
    {
        if (self_)
        {
            const int dstObjId = dstId / objSize_;
            const int srcObjId = srcId / objSize_;

            if (dstObjId == srcObjId)
                return false;
        }
        return true;
    }

private:
    bool self_ {false};
    int objSize_ {0};
};
MIRHEO_TYPE_NAME(LJAwarenessObject, "LJAwarenessObject");

class LJAwarenessRod
{
public:
    using ParamsType = LJAwarenessParamsRod;
    
    LJAwarenessRod(int minSegmentsDist) :
        minSegmentsDist_(minSegmentsDist)
    {}

    LJAwarenessRod(const ParamsType& params) :
        LJAwarenessRod(params.minSegmentsDist)
    {}

    void setup(LocalParticleVector *lpv1, LocalParticleVector *lpv2)
    {
        auto rv1 = dynamic_cast<RodVector*>(lpv1->parent());
        auto rv2 = dynamic_cast<RodVector*>(lpv2->parent());

        self_ = false;
        if (rv1 != nullptr && rv2 != nullptr && lpv1 == lpv2)
        {
            self_ = true;
            objSize_ = rv1->getObjectSize();
        }
    }

    __D__ inline bool interact(int srcId, int dstId) const
    {
        if (self_)
        {
            const int dstObjId = dstId / objSize_;
            const int srcObjId = srcId / objSize_;

            if (dstObjId == srcObjId)
            {
                const int srcSegId = (dstId % objSize_) / 5;
                const int dstSegId = (srcId % objSize_) / 5;

                if (math::abs(srcSegId - dstSegId) <= minSegmentsDist_)
                    return false;
            }
        }
        return true;
    }

private:
    bool self_ {false};
    int objSize_ {0};
    int minSegmentsDist_{0};
};
MIRHEO_TYPE_NAME(LJAwarenessRod, "LJAwarenessRod");

template <class Awareness>
class PairwiseRepulsiveLJ : public PairwiseKernel, public ParticleFetcher
{
public:

    using ViewType     = PVview;
    using ParticleType = Particle;
    using HandlerType  = PairwiseRepulsiveLJ;
    using ParamsType   = LJParams;
    
    PairwiseRepulsiveLJ(real rc, real epsilon, real sigma, real maxForce, Awareness awareness) :
        ParticleFetcher(rc),
        sigma2_(sigma*sigma),
        maxForce_(maxForce),
        epsx24_sigma2_(24.0_r * epsilon / (sigma * sigma)),
        awareness_(awareness)
    {
        constexpr real sigmaFactor = 1.1224620483_r; // 2^(1/6)
        const real rm = sigmaFactor * sigma; // F(rm) = 0

        if (rm > rc)
        {
            const real maxSigma = rc / sigmaFactor;
            die("RepulsiveLJ: rm = %g > rc = %g; sigma must be lower than %g or rc must be larger than %g",
                rm, rc, maxSigma, rm);
        }
    }

    PairwiseRepulsiveLJ(real rc, const ParamsType& p, __UNUSED real dt, __UNUSED long seed=42424242) :
        PairwiseRepulsiveLJ{rc,
                            p.epsilon,
                            p.sigma,
                            p.maxForce,
                            mpark::get<typename Awareness::ParamsType>(p.varLJAwarenessParams)}
    {}

    __D__ inline real3 operator()(ParticleType dst, int dstId, ParticleType src, int srcId) const
    {
        constexpr real tolerance = 1e-6_r;
        if (!awareness_.interact(src.i1, dst.i1))
            return make_real3(0.0_r);
        
        const real3 dr = dst.r - src.r;
        const real dr2 = dot(dr, dr);

        if (dr2 > rc2_ || dr2 < tolerance)
            return make_real3(0.0_r);

        const real rs2 = sigma2_ / dr2;
        const real rs4 = rs2*rs2;
        const real rs8 = rs4*rs4;
        const real rs14 = rs8*(rs4*rs2);

        const real IfI = epsx24_sigma2_ * (2*rs14 - rs8);

        return dr * math::min(math::max(IfI, 0.0_r), maxForce_);
    }

    __D__ inline ForceAccumulator getZeroedAccumulator() const {return ForceAccumulator();}

    const HandlerType& handler() const
    {
        return (const HandlerType&) (*this);
    }

    void setup(LocalParticleVector *lpv1, LocalParticleVector *lpv2,
               __UNUSED CellList *cl1, __UNUSED CellList *cl2, __UNUSED const MirState *state) override
    {
        awareness_.setup(lpv1, lpv2);
    }

    static std::string getTypeName()
    {
        return constructTypeName<Awareness>("PairwiseRepulsiveLJ");
    }

private:

    real sigma2_, maxForce_;
    real epsx24_sigma2_;

    Awareness awareness_;
};

} // namespace mirheo
