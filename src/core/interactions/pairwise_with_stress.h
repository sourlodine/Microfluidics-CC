#pragma once
#include "interface.h"
#include "pairwise.h"
#include "pairwise_interactions/stress_wrapper.h"

#include <core/datatypes.h>
#include <map>

template<class PairwiseInteraction>
class InteractionPair_withStress : public Interaction
{
public:
    enum class InteractionType { Regular, Halo };

    InteractionPair_withStress(const YmrState *state, std::string name, std::string stressName, float rc, float stressPeriod, PairwiseInteraction pair);
    ~InteractionPair_withStress();
    
    void setSpecificPair(std::string pv1name, std::string pv2name, PairwiseInteraction pair);

    void regular(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream) override;
    void halo   (ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream) override;
    void setPrerequisites(ParticleVector *pv1, ParticleVector *pv2);

private:
    float stressPeriod;
    float lastStressTime{-1e6};

    std::map<ParticleVector*, float> pv2lastStressTime;
    std::string stressName; 

    InteractionPair<PairwiseInteraction> interaction;
    InteractionPair<PairwiseStressWrapper<PairwiseInteraction>> interactionWithStress;
};
