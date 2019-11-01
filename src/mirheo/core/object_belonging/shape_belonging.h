#pragma once

#include "object_belonging.h"

namespace mirheo
{

template <class Shape>
class ShapeBelongingChecker : public ObjectBelongingChecker_Common
{
public:
    using ObjectBelongingChecker_Common::ObjectBelongingChecker_Common;

    void tagInner(ParticleVector *pv, CellList *cl, cudaStream_t stream) override;
};

} // namespace mirheo
