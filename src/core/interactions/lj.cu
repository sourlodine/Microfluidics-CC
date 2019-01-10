#include "lj.h"
#include <memory>
#include "pairwise.h"
#include "pairwise_interactions/lj.h"
#include "pairwise_interactions/lj_object_aware.h"


InteractionLJ::InteractionLJ(const YmrState *state, std::string name, float rc, float epsilon, float sigma, float maxForce, bool objectAware, bool allocate) :
    Interaction(state, name, rc),
    objectAware(objectAware)
{
    if (!allocate) return;

    if (objectAware) {
        Pairwise_LJObjectAware lj(rc, epsilon, sigma, maxForce);
        impl = std::make_unique<InteractionPair<Pairwise_LJObjectAware>> (state, name, rc, lj);
    }
    else {
        Pairwise_LJ lj(rc, epsilon, sigma, maxForce);
        impl = std::make_unique<InteractionPair<Pairwise_LJ>> (state, name, rc, lj);
    }
}

InteractionLJ::InteractionLJ(const YmrState *state, std::string name, float rc, float epsilon, float sigma, float maxForce, bool objectAware) :
    InteractionLJ(state, name, rc, epsilon, sigma, maxForce, objectAware, true)
{}

InteractionLJ::~InteractionLJ() = default;

void InteractionLJ::setPrerequisites(ParticleVector* pv1, ParticleVector* pv2)
{
    impl->setPrerequisites(pv1, pv2);
}

void InteractionLJ::initStep(ParticleVector *pv1, ParticleVector *pv2, cudaStream_t stream)
{
    impl->initStep(pv1, pv2, stream);
}

void InteractionLJ::regular(ParticleVector *pv1, ParticleVector *pv2,
                            CellList *cl1, CellList *cl2,
                            cudaStream_t stream)
{
    impl->regular(pv1, pv2, cl1, cl2, stream);
}

void InteractionLJ::halo(ParticleVector *pv1, ParticleVector *pv2,
                         CellList *cl1, CellList *cl2,
                         cudaStream_t stream)
{
    impl->halo(pv1, pv2, cl1, cl2, stream);
}

void InteractionLJ::setSpecificPair(ParticleVector* pv1, ParticleVector* pv2, 
                                    float epsilon, float sigma, float maxForce)
{
    if (objectAware) {
        Pairwise_LJObjectAware lj(rc, epsilon, sigma, maxForce);
        auto ptr = static_cast< InteractionPair<Pairwise_LJObjectAware>* >(impl.get());
        ptr->setSpecificPair(pv1->name, pv2->name, lj);
    }
    else {
        Pairwise_LJ lj(rc, epsilon, sigma, maxForce);
        auto ptr = static_cast< InteractionPair<Pairwise_LJ>* >(impl.get());
        ptr->setSpecificPair(pv1->name, pv2->name, lj);
    }
}

