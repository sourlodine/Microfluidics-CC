#pragma once

#include <core/containers.h>
#include <core/datatypes.h>
#include "object_vector.h"

class MembraneVector: public ObjectVector
{
public:
    MembraneVector(std::string name, const YmrState *state, float mass, std::shared_ptr<MembraneMesh> mptr, const int nObjects = 0) :
        ObjectVector( name, state, mass, mptr->getNvertices(),
                      new LocalObjectVector(this, mptr->getNvertices(), nObjects),
                      new LocalObjectVector(this, mptr->getNvertices(), 0) )
    {
        mesh = std::move(mptr);
    }

    virtual ~MembraneVector() = default;
};
