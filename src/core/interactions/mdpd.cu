#include "mdpd.h"
#include "pairwise.h"
#include "pairwise_interactions/density.h"
#include "pairwise_interactions/mdpd.h"

#include <core/celllist.h>
#include <core/utils/common.h>
#include <core/utils/make_unique.h>
#include <core/pvs/particle_vector.h>

#include <memory>



InteractionDensity::InteractionDensity(const YmrState *state, std::string name, float rc) :
    Interaction(state, name, rc)
{
    Pairwise_density density(rc);
    impl = std::make_unique<InteractionPair<Pairwise_density>> (state, name, rc, density);
}

InteractionDensity::~InteractionDensity() = default;

void InteractionDensity::setPrerequisites(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2)
{
    impl->setPrerequisites(pv1, pv2, cl1, cl2);

    pv1->requireDataPerParticle<float>(ChannelNames::densities, ExtraDataManager::CommunicationMode::None, ExtraDataManager::PersistenceMode::None);
    pv2->requireDataPerParticle<float>(ChannelNames::densities, ExtraDataManager::CommunicationMode::None, ExtraDataManager::PersistenceMode::None);
    
    cl1->requireExtraDataPerParticle<float>(ChannelNames::densities);
    cl2->requireExtraDataPerParticle<float>(ChannelNames::densities);
}

std::vector<Interaction::InteractionChannel> InteractionDensity::getIntermediateOutputChannels() const
{
    return {{ChannelNames::densities, Interaction::alwaysActive}};
}
std::vector<Interaction::InteractionChannel> InteractionDensity::getFinalOutputChannels() const
{
    return {};
}

void InteractionDensity::local(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream)
{
    impl->local(pv1, pv2, cl1, cl2, stream);
}

void InteractionDensity::halo (ParticleVector *pv1, ParticleVector *pv2, CellList *cl1, CellList *cl2, cudaStream_t stream)
{
    impl->halo(pv1, pv2, cl1, cl2, stream);
}






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

    pv1->requireDataPerParticle<float>(ChannelNames::densities, ExtraDataManager::CommunicationMode::None, ExtraDataManager::PersistenceMode::None);
    pv2->requireDataPerParticle<float>(ChannelNames::densities, ExtraDataManager::CommunicationMode::None, ExtraDataManager::PersistenceMode::None);
    
    cl1->requireExtraDataPerParticle<float>(ChannelNames::densities);
    cl2->requireExtraDataPerParticle<float>(ChannelNames::densities);
}

std::vector<Interaction::InteractionChannel> InteractionMDPD::getIntermediateInputChannels() const
{
    return {{ChannelNames::densities, Interaction::alwaysActive}};
}

std::vector<Interaction::InteractionChannel> InteractionMDPD::getFinalOutputChannels() const
{
    return impl->getFinalOutputChannels();
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


