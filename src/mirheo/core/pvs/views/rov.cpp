#include "rov.h"

#include <mirheo/core/pvs/rigid_object_vector.h>

namespace mirheo
{

ROVview::ROVview(RigidObjectVector *rov, LocalRigidObjectVector *lrov) :
    OVview(rov, lrov)
{
    motions = lrov->dataPerObject.getData<RigidMotion>(ChannelNames::motions)->devPtr();

    J   = rov->getInertialTensor();
    J_1 = 1.0 / J;
}

ROVviewWithOldMotion::ROVviewWithOldMotion(RigidObjectVector* rov, LocalRigidObjectVector* lrov) :
    ROVview(rov, lrov)
{
    old_motions = lrov->dataPerObject.getData<RigidMotion>(ChannelNames::oldMotions)->devPtr();
}

} // namespace mirheo
