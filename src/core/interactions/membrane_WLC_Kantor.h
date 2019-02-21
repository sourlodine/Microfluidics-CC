#pragma once

#include "membrane.new.h"
#include "membrane/parameters.h"

#include <memory>

class MembraneWLCKantor : public InteractionMembraneNew
{
public:
    MembraneWLCKantor(const YmrState *state, std::string name,
                      MembraneParameters parameters, KantorBendingParameters kantorParams,
                      bool stressFree, float growUntil);
    ~MembraneWLCKantor();
};
