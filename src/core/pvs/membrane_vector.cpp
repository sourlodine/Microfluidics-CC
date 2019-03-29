#include "membrane_vector.h"

MembraneVector::MembraneVector(const YmrState *state, std::string name, float mass, std::shared_ptr<MembraneMesh> mptr, int nObjects) :
    ObjectVector( state, name, mass, mptr->getNvertices(),
                  new LocalObjectVector(this, mptr->getNvertices(), nObjects),
                  new LocalObjectVector(this, mptr->getNvertices(), 0) )
{
    mesh = std::move(mptr);
}

MembraneVector::~MembraneVector() = default;
