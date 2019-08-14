#include "interface.h"

Wall::Wall(const MirState *state, std::string name) :
    MirSimulationObject(state, name)
{}

Wall::~Wall() = default;

void Wall::setPrerequisites(__UNUSED ParticleVector *pv)
{}

SDF_basedWall::~SDF_basedWall() = default;
