#pragma once

#include "membrane.h"
#include "sdpd.h"

#include <map>
#include <memory>
#include <string>

namespace InteractionFactory
{

std::shared_ptr<InteractionMembrane>
createInteractionMembrane(const YmrState *state, std::string name,
                          std::string shearDesc, std::string bendingDesc,
                          const std::map<std::string, float>& parameters,
                          bool stressFree, float growUntil);

std::shared_ptr<BasicInteractionSDPD>
createPairwiseSDPD(const YmrState *state, std::string name, float rc, float viscosity, float kBT,
                   const std::string& EOS, const std::map<std::string, float>& parameters);


} // namespace InteractionFactory
