#include "mdpd.h"
#include "pairwise.h"
#include "pairwise_interactions/mdpd.h"

#include <core/celllist.h>
#include <core/utils/make_unique.h>
#include <core/pvs/particle_vector.h>

#include <memory>

InteractionMDPD::InteractionMDPD(const YmrState *state, std::string name, float rc, float rd, float a, float b, float gamma, float kbt, float power, bool allocateImpl) :
    Interaction(state, name, rc),
    rd(rd), a(a), b(b), gamma(gamma), kbt(kbt), power(power)
{
    if (allocateImpl) {
        Pairwise_MDPD mdpd(rc, rd, a, b, gamma, kbt, state->dt, power);
        impl = std::make_unique<InteractionPair<Pairwise_MDPD>> (state, name, rc, mdpd);
    }
}

InteractionMDPD::InteractionMDPD(const YmrState *state, std::string name, float rc, float rd, float a, float b, float gamma, float kbt, float power) :
    InteractionMDPD(state, name, rc, rd, a, b, gamma, kbt, power, true)
{}

InteractionMDPD::~InteractionMDPD() = default;

void InteractionMDPD::setPrerequisites(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2)
{
    impl->setPrerequisites(pv1, pv2, cl1, cl2);

    // cl1->requireExtraDataPerParticle(ChannelNames::densities, Celllist::InteractionOutput::Intermediate);
    // cl2->requireExtraDataPerParticle(ChannelNames::densities, Celllist::InteractionOutput::Intermediate);
    
    cl1->setNeededForOutput();
    cl2->setNeededForOutput();
}

void InteractionMDPD::local(ParticleVector *pv1, ParticleVector *pv2,
                            CellList *cl1, CellList *cl2,
                            cudaStream_t stream)
{
    impl->local(pv1, pv2, cl1, cl2, stream);
}

void InteractionMDPD::halo(ParticleVector *pv1, ParticleVector *pv2,
                           CellList *cl1, CellList *cl2,
                           cudaStream_t stream)
{
    impl->halo(pv1, pv2, cl1, cl2, stream);
}

void InteractionMDPD::setSpecificPair(ParticleVector* pv1, ParticleVector* pv2, 
                                      float a, float b, float gamma, float kbt, float power)
{
    if (a     == Default) a     = this->a;
    if (b     == Default) b     = this->b;
    if (gamma == Default) gamma = this->gamma;
    if (kbt   == Default) kbt   = this->kbt;
    if (power == Default) power = this->power;

    Pairwise_MDPD mdpd(this->rc, this->rd, a, b, gamma, kbt, state->dt, power);
    auto ptr = static_cast< InteractionPair<Pairwise_MDPD>* >(impl.get());
    
    ptr->setSpecificPair(pv1->name, pv2->name, mdpd);
}


