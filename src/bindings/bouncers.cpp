#include "bindings.h"
#include "class_wrapper.h"

#include <core/analytical_shapes/api.h>
#include <core/bouncers/from_mesh.h>
#include <core/bouncers/from_rod.h>
#include <core/bouncers/from_shape.h>
#include <core/bouncers/interface.h>

#include <map>
#include <memory>

using namespace pybind11::literals;

static std::map<std::string, float>
castToMap(const py::kwargs& kwargs, const std::string& name)
{
    std::map<std::string, float> parameters;
    
    for (const auto& item : kwargs)
    {
        std::string key;
        try {
            key = py::cast<std::string>(item.first);
        }
        catch (const py::cast_error& e) {
            die("Could not cast one of the arguments in bouncer '%s' to string", name.c_str());
        }
        try {
            parameters[key] = py::cast<float>(item.second);
        }
        catch (const py::cast_error& e) {
            die("Could not cast argument '%s' in bouncer '%s': wrong type", key.c_str(), name.c_str());
        }
    }
    return parameters;
}

static VarBounceKernel readBounceKernel(const std::string& kernel, const py::kwargs& kwargs, const std::string& name)
{
    auto params = castToMap(kwargs, name);
    VarBounceKernel varBounceKernel;

    if (kernel == "bounce_back")
    {
        varBounceKernel = BounceBack{};
    }
    else if (kernel == "bounce_maxwell")
    {
        auto it = params.find("kBT");
        if (it == params.end())
            die("missing parameter 'kBT' in bouncer '%s'", name.c_str());

        BounceMaxwell bouncer(it->second);
        varBounceKernel = bouncer;
    }
    else
    {
        die("Unrecognized bounce kernel '%s' in '%s'\n", kernel.c_str(), name.c_str());
    }
    return varBounceKernel;
}
    

void exportBouncers(py::module& m)
{
    py::handlers_class<Bouncer> pybounce(m, "Bouncer", R"(
        Base class for bouncing particles off the objects.
        Take bounce kernel as argument:
        
        * **kernel** = "bounce_back":
            bounces back the particle.

        * **kernel** = "bounce_maxwell":
            reinsert particle at the collision point with a velocity drawn from a maxwellian distribution.
    )");

    
    py::handlers_class<BounceFromMesh>(m, "Mesh", pybounce, R"(
        This bouncer will use the triangular mesh associated with objects to detect boundary crossings.
        Therefore it can only be created for Membrane and Rigid Object types of object vectors.
        Due to numerical precision, about :math:`1` of :math:`10^5 - 10^6` mesh crossings will not be detected, therefore it is advised to use that bouncer in
        conjunction with correction option provided by the Object Belonging Checker, see :ref:`user-belongers`.
        
        .. note::
            In order to prevent numerical instabilities in case of light membrane particles,
            the new velocity of the bounced particles will be a random vector drawn from the Maxwell distibution of given temperature
            and added to the velocity of the mesh triangle at the collision point.
    )")
        .def(py::init([](const MirState *state, const std::string& name, const std::string& kernel, const py::kwargs& kwargs)
                      {
                          auto varBounceKernel = readBounceKernel(kernel, kwargs, name);
                          return std::make_shared<BounceFromMesh>(state, name, varBounceKernel);
                      }),
                      "state"_a, "name"_a, "kernel"_a, R"(
            Args:
                name: name of the bouncer
                kernel: the kernel used to bounce the particles (see :any:`Bouncer`)
        )");
        
    py::handlers_class<BounceFromRigidShape<Capsule>>(m, "Capsule", pybounce, R"(
        This bouncer will use the analytical capsule representation of the rigid objects to perform the bounce.
        No additional correction from the Object Belonging Checker is usually required.
        The velocity of the particles bounced from the cylinder is reversed with respect to the boundary velocity at the contact point.
    )")
        .def(py::init([](const MirState *state, const std::string& name, const std::string& kernel, const py::kwargs& kwargs)
                      {
                          auto varBounceKernel = readBounceKernel(kernel, kwargs, name);
                          return std::make_shared<BounceFromRigidShape<Capsule>>(state, name, varBounceKernel);
                      }),
            "state"_a, "name"_a, "kernel"_a, R"(
            Args:
                name: name of the checker
                kernel: the kernel used to bounce the particles (see :any:`Bouncer`)
            
        )");

    py::handlers_class<BounceFromRigidShape<Cylinder>>(m, "Cylinder", pybounce, R"(
        This bouncer will use the analytical cylinder representation of the rigid objects to perform the bounce.
        No additional correction from the Object Belonging Checker is usually required.
        The velocity of the particles bounced from the cylinder is reversed with respect to the boundary velocity at the contact point.
    )")
        .def(py::init([](const MirState *state, const std::string& name, const std::string& kernel, const py::kwargs& kwargs)
                      {
                          auto varBounceKernel = readBounceKernel(kernel, kwargs, name);
                          return std::make_shared<BounceFromRigidShape<Cylinder>>(state, name, varBounceKernel);
                      }),
            "state"_a, "name"_a, "kernel"_a, R"(
            Args:
                name: name of the checker
                kernel: the kernel used to bounce the particles (see :any:`Bouncer`)
            
        )");

    py::handlers_class<BounceFromRigidShape<Ellipsoid>>(m, "Ellipsoid", pybounce, R"(
        This bouncer will use the analytical ellipsoid representation of the rigid objects to perform the bounce.
        No additional correction from the Object Belonging Checker is usually required.
        The velocity of the particles bounced from the ellipsoid is reversed with respect to the boundary velocity at the contact point.
    )")
        .def(py::init([](const MirState *state, const std::string& name, const std::string& kernel, const py::kwargs& kwargs)
                      {
                          auto varBounceKernel = readBounceKernel(kernel, kwargs, name);
                          return std::make_shared<BounceFromRigidShape<Ellipsoid>>(state, name, varBounceKernel);
                      }),
            "state"_a, "name"_a, "kernel"_a, R"(
            Args:
                name: name of the checker
                kernel: the kernel used to bounce the particles (see :any:`Bouncer`)
            
        )");

    py::handlers_class<BounceFromRod>(m, "Rod", pybounce, R"(
        This bouncer will use the analytical representation of enlarged segments by a given radius.
        The velocity of the particles bounced from the segments is reversed with respect to the boundary velocity at the contact point.
    )")
        .def(py::init([](const MirState *state, const std::string& name, float radius, const std::string& kernel, const py::kwargs& kwargs)
                      {
                          auto varBounceKernel = readBounceKernel(kernel, kwargs, name);
                          return std::make_shared<BounceFromRod>(state, name, radius, varBounceKernel);
                      }),
            "state"_a, "name"_a, "radius"_a, "kernel"_a, R"(
            Args:
                name: name of the checker
                radius: radius of the segments
                kernel: the kernel used to bounce the particles (see :any:`Bouncer`)
            
        )");
}

