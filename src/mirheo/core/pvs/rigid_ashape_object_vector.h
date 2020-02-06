#pragma once

#include "rigid_object_vector.h"

namespace mirheo
{

template <class Shape>
class RigidShapedObjectVector : public RigidObjectVector
{
public:
    RigidShapedObjectVector(const MirState *state, const std::string& name, real mass, int objSize,
                            Shape shape, int nObjects = 0);
    
    RigidShapedObjectVector(const MirState *state, const std::string& name, real mass, int objSize,
                            Shape shape, std::shared_ptr<Mesh> mesh, int nObjects = 0);
        
    virtual ~RigidShapedObjectVector();

    const Shape& getShape() const {return shape_;}
    
private:
    Shape shape_;
};

} // namespace mirheo
