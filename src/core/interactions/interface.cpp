#include "interface.h"

Interaction::Interaction(const YmrState *state, std::string name, float rc) :
    YmrSimulationObject(state, name),
    rc(rc)
{}

Interaction::~Interaction() = default;

void Interaction::setPrerequisites(ParticleVector *pv1, ParticleVector *pv2)
{}

void Interaction::initStep(ParticleVector *pv1, ParticleVector *pv2, cudaStream_t stream)
{}
