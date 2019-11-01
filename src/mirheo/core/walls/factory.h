#pragma once

#include "interface.h"

#include "simple_stationary_wall.h"
#include "stationary_walls/box.h"
#include "stationary_walls/cylinder.h"
#include "stationary_walls/plane.h"
#include "stationary_walls/sdf.h"
#include "stationary_walls/sphere.h"
#include "velocity_field/oscillate.h"
#include "velocity_field/rotate.h"
#include "velocity_field/translate.h"
#include "wall_with_velocity.h"

#include <memory>

namespace mirheo
{

class ParticleVector;
class CellList;


namespace WallFactory
{
inline std::shared_ptr<SimpleStationaryWall<StationaryWall_Sphere>>
createSphereWall(const MirState *state, const std::string& name, real3 center, real radius, bool inside)
{
    StationaryWall_Sphere sphere(center, radius, inside);
    return std::make_shared<SimpleStationaryWall<StationaryWall_Sphere>> (name, state, std::move(sphere));
}

inline std::shared_ptr<SimpleStationaryWall<StationaryWall_Box>>
createBoxWall(const MirState *state, const std::string& name, real3 low, real3 high, bool inside)
{
    StationaryWall_Box box(low, high, inside);
    return std::make_shared<SimpleStationaryWall<StationaryWall_Box>> (name, state, std::move(box));
}

inline std::shared_ptr<SimpleStationaryWall<StationaryWall_Cylinder>>
createCylinderWall(const MirState *state, const std::string& name, real2 center, real radius, const std::string& axis, bool inside)
{
    StationaryWall_Cylinder::Direction dir;
    if (axis == "x") dir = StationaryWall_Cylinder::Direction::x;
    if (axis == "y") dir = StationaryWall_Cylinder::Direction::y;
    if (axis == "z") dir = StationaryWall_Cylinder::Direction::z;

    StationaryWall_Cylinder cylinder(center, radius, dir, inside);
    return std::make_shared<SimpleStationaryWall<StationaryWall_Cylinder>> (name, state, std::move(cylinder));
}

inline std::shared_ptr<SimpleStationaryWall<StationaryWall_Plane>>
createPlaneWall(const MirState *state, const std::string& name, real3 normal, real3 pointThrough)
{
    StationaryWall_Plane plane(normalize(normal), pointThrough);
    return std::make_shared<SimpleStationaryWall<StationaryWall_Plane>> (name, state, std::move(plane));
}

inline std::shared_ptr<SimpleStationaryWall<StationaryWall_SDF>>
createSDFWall(const MirState *state, const std::string& name, const std::string& sdfFilename, real3 h)
{
    StationaryWall_SDF sdf(state, sdfFilename, h);
    return std::make_shared<SimpleStationaryWall<StationaryWall_SDF>> (name, state, std::move(sdf));
}

// Moving walls

inline std::shared_ptr<WallWithVelocity<StationaryWall_Cylinder, VelocityField_Rotate>>
createMovingCylinderWall(const MirState *state, const std::string& name, real2 center, real radius, const std::string& axis, real omega, bool inside)
{
    StationaryWall_Cylinder::Direction dir;
    if (axis == "x") dir = StationaryWall_Cylinder::Direction::x;
    if (axis == "y") dir = StationaryWall_Cylinder::Direction::y;
    if (axis == "z") dir = StationaryWall_Cylinder::Direction::z;

    StationaryWall_Cylinder cylinder(center, radius, dir, inside);
    real3 omega3, center3;
    switch (dir)
    {
    case StationaryWall_Cylinder::Direction::x :
        center3 = {0.0_r, center.x, center.y};
        omega3  = {omega,    0.0_r,    0.0_r};
        break;

    case StationaryWall_Cylinder::Direction::y :
        center3 = {center.x, 0.0_r, center.y};
        omega3  = {0.0_r,    omega,    0.0_r};
        break;

    case StationaryWall_Cylinder::Direction::z :
        center3 = {center.x, center.y, 0.0_r};
        omega3  = {0.0_r,    0.0_r,    omega};
        break;
    }
    VelocityField_Rotate rotate(omega3, center3);

    return std::make_shared<WallWithVelocity<StationaryWall_Cylinder, VelocityField_Rotate>> (name, state, std::move(cylinder), std::move(rotate));
}

inline std::shared_ptr<WallWithVelocity<StationaryWall_Plane, VelocityField_Translate>>
createMovingPlaneWall(const MirState *state, const std::string& name, real3 normal, real3 pointThrough, real3 velocity)
{
    StationaryWall_Plane plane(normalize(normal), pointThrough);
    VelocityField_Translate translate(velocity);
    return std::make_shared<WallWithVelocity<StationaryWall_Plane, VelocityField_Translate>> (name, state, std::move(plane), std::move(translate));
}

inline std::shared_ptr<WallWithVelocity<StationaryWall_Plane, VelocityField_Oscillate>>
createOscillatingPlaneWall(const MirState *state, const std::string& name, real3 normal, real3 pointThrough, real3 velocity, real period)
{
    StationaryWall_Plane plane(normalize(normal), pointThrough);
    VelocityField_Oscillate osc(velocity, period);
    return std::make_shared<WallWithVelocity<StationaryWall_Plane, VelocityField_Oscillate>> (name, state, std::move(plane), std::move(osc));
}
} // namespace WallFactory

} // namespace mirheo
