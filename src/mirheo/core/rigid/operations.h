#pragma once

#include <mirheo/core/pvs/views/rov.h>

namespace mirheo
{

namespace RigidOperations
{
enum class ApplyTo { PositionsOnly, PositionsAndVelocities };

void collectRigidForces(const ROVview& view, cudaStream_t stream);

void applyRigidMotion(const ROVview& view, const PinnedBuffer<real4>& initialPositions,
                      ApplyTo action, cudaStream_t stream);

void clearRigidForcesFromMotions(const ROVview& view, cudaStream_t stream);

} // namespace RigidOperations

} // namespace mirheo
