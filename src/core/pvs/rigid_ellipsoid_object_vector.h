#pragma once

#include "rigid_object_vector.h"
#include <core/utils/pytypes.h>


class RigidEllipsoidObjectVector : public RigidObjectVector
{
public:
    float3 axes;

    RigidEllipsoidObjectVector(std::string name, const YmrState *state, float mass, const int objSize,
                               PyTypes::float3 axes, const int nObjects = 0);

    RigidEllipsoidObjectVector(std::string name, const YmrState *state, float mass, const int objSize,
                               PyTypes::float3 axes, std::shared_ptr<Mesh> mesh,
                               const int nObjects = 0);
        
    virtual ~RigidEllipsoidObjectVector() {};
};


