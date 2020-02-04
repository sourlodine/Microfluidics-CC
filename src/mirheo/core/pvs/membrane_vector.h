#pragma once

#include "object_vector.h"

#include <mirheo/core/mesh/membrane.h>

namespace mirheo
{

class MembraneVector: public ObjectVector
{
public:
    MembraneVector(const MirState *state, const std::string& name, real mass, std::shared_ptr<MembraneMesh> mptr, int nObjects = 0);
    ~MembraneVector();

    ConfigDictionary writeSnapshot(Dumper &dumper) const override;
};

} // namespace mirheo
