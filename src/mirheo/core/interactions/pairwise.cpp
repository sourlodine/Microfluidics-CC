#include "pairwise.h"

#include <mirheo/core/utils/config.h>

#include <cassert>

namespace mirheo
{

PairwiseInteraction::PairwiseInteraction(const MirState *state, Loader& loader,
                                         const ConfigObject& config) :
    PairwiseInteraction{
        state, config["name"], config["rc"],
        loader.load<VarPairwiseParams>(config["varParams"]),
        loader.load<VarStressParams>(config["varStressParams"]),
    }
{
    assert(config["__type"].getString() == "PairwiseInteraction");
}

void PairwiseInteraction::saveSnapshotAndRegister(Saver& saver)
{
    saver.registerObject<PairwiseInteraction>(
            this, _saveSnapshot(saver, "PairwiseInteraction"));
}

ConfigObject PairwiseInteraction::_saveSnapshot(Saver& saver, const std::string& typeName)
{
    ConfigObject config = Interaction::_saveSnapshotWithoutImpl(saver, typeName);
    config.emplace("rc",              saver(getCutoffRadius()));
    config.emplace("varParams",       saver(varParams_));
    config.emplace("varStressParams", saver(varStressParams_));
    return config;
}

} // namespace mirheo
