#include <pybind11/stl.h>
#include <pybind11/functional.h>

#include <core/initial_conditions/from_array.h>
#include <core/initial_conditions/interface.h>
#include <core/initial_conditions/membrane.h>
#include <core/initial_conditions/restart.h>
#include <core/initial_conditions/rigid.h>
#include <core/initial_conditions/rod.h>
#include <core/initial_conditions/uniform.h>
#include <core/initial_conditions/uniform_filtered.h>
#include <core/initial_conditions/uniform_sphere.h>

#include <core/utils/pytypes.h>

#include "bindings.h"
#include "class_wrapper.h"

using namespace pybind11::literals;

void exportInitialConditions(py::module& m)
{
    py::handlers_class<InitialConditions> pyic(m, "InitialConditions", R"(
            Base class for initial conditions
        )");

    

    py::handlers_class<FromArrayIC>(m, "FromArray", pyic, R"(
        Set particles according to given position and velocity arrays.
    )")
        .def(py::init<const PyTypes::VectorOfFloat3&, const PyTypes::VectorOfFloat3&>(), "pos"_a, "vel"_a, R"(
            Args:
                pos: array of positions
                vel: array of velocities
        )");
        
    py::handlers_class<MembraneIC>(m, "Membrane", pyic, R"(
        Can only be used with Membrane Object Vector, see :ref:`user-ic`. These IC will initialize the particles of each object
        according to the mesh associated with Membrane, and then the objects will be translated/rotated according to the provided initial conditions.
    )")
        .def(py::init<PyTypes::VectorOfFloat7, float>(), "com_q"_a, "global_scale"_a=1.0, R"(
            Args:
                com_q:
                    List describing location and rotation of the created objects.               
                    One entry in the list corresponds to one object created.                          
                    Each entry consist of 7 floats: *<com_x> <com_y> <com_z>  <q_x> <q_y> <q_z> <q_w>*, where    
                    *com* is the center of mass of the object, *q* is the quaternion of its rotation,
                    not necessarily normalized 
                global_scale:
                    All the membranes will be scaled by that value. Useful to implement membranes growth so that they
                    can fill the space with high volume fraction                                        
        )");

    py::handlers_class<RestartIC>(m, "Restart", pyic, R"(
        Read the state (particle coordinates and velocities, other relevant data for objects is **not implemented yet**)
    )")
        .def(py::init<std::string>(),"path"_a = "restart/", R"(

            Args:
                path: folder where the restart files reside. The exact filename will be like this: <path>/<PV name>.chk
        )");
        
    py::handlers_class<RigidIC>(m, "Rigid", pyic, R"(
        Can only be used with Rigid Object Vector or Rigid Ellipsoid, see :ref:`user-ic`. These IC will initialize the particles of each object
        according to the template .xyz file and then the objects will be translated/rotated according to the provided initial conditions.
            
    )")
        .def(py::init<PyTypes::VectorOfFloat7, std::string>(), "com_q"_a, "xyz_filename"_a, R"(
            Args:
                com_q:
                    List describing location and rotation of the created objects.               
                    One entry in the list corresponds to one object created.                          
                    Each entry consist of 7 floats: *<com_x> <com_y> <com_z>  <q_x> <q_y> <q_z> <q_w>*, where    
                    *com* is the center of mass of the object, *q* is the quaternion of its rotation,
                    not necessarily normalized 
                xyz_filename:
                    Template that describes the positions of the body particles before translation or        
                    rotation is applied. Standard .xyz file format is used with first line being             
                    the number of particles, second comment, third and onwards - particle coordinates.       
                    The number of particles in the file must be the same as in number of particles per object
                    in the corresponding PV
        )")
        .def(py::init<PyTypes::VectorOfFloat7, const PyTypes::VectorOfFloat3&>(), "com_q"_a, "coords"_a, R"(
            Args:
                com_q:
                    List describing location and rotation of the created objects.               
                    One entry in the list corresponds to one object created.                          
                    Each entry consist of 7 floats: *<com_x> <com_y> <com_z>  <q_x> <q_y> <q_z> <q_w>*, where    
                    *com* is the center of mass of the object, *q* is the quaternion of its rotation,
                    not necessarily normalized 
                coords:
                    Template that describes the positions of the body particles before translation or        
                    rotation is applied.       
                    The number of coordinates must be the same as in number of particles per object
                    in the corresponding PV
        )")
        .def(py::init<PyTypes::VectorOfFloat7, const PyTypes::VectorOfFloat3&, const PyTypes::VectorOfFloat3&>(),
             "com_q"_a, "coords"_a, "init_vels"_a, R"(
            Args:
                com_q:
                    List describing location and rotation of the created objects.               
                    One entry in the list corresponds to one object created.                          
                    Each entry consist of 7 floats: *<com_x> <com_y> <com_z>  <q_x> <q_y> <q_z> <q_w>*, where    
                    *com* is the center of mass of the object, *q* is the quaternion of its rotation,
                    not necessarily normalized 
                coords:
                    Template that describes the positions of the body particles before translation or        
                    rotation is applied.       
                    The number of coordinates must be the same as in number of particles per object
                    in the corresponding PV
                com_q:
                    List specifying initial Center-Of-Mass velocities of the bodies.               
                    One entry (list of 3 floats) in the list corresponds to one object 
        )");
    

    py::handlers_class<RodIC>(m, "Rod", pyic, R"(
        Can only be used with Rod Vector. These IC will initialize the particles of each rod
        according to the the given explicit center-line position aand torsion mapping and then 
        the objects will be translated/rotated according to the provided initial conditions.
            
    )")
        .def(py::init<PyTypes::VectorOfFloat7, std::function<PyTypes::float3(float)>, std::function<float(float)>>(),
             "com_q"_a, "center_line"_a, "torsion"_a, R"(
            Args:
                com_q:
                    List describing location and rotation of the created objects.               
                    One entry in the list corresponds to one object created.                          
                    Each entry consist of 7 floats: *<com_x> <com_y> <com_z>  <q_x> <q_y> <q_z> <q_w>*, where    
                    *com* is the center of mass of the object, *q* is the quaternion of its rotation,
                    not necessarily normalized 
                center_line:
                    explicit mapping :math:`\mathbf{r} : [0,1] \rightarrow R^3`. 
                    Assume :math:`|r'(s)|` is constant for all :math:`s \in [0,1]`.
                torsion:
                    explicit mapping :math:`\tau : [0,1] \rightarrow R`.
        )");

    py::handlers_class<UniformIC>(m, "Uniform", pyic, R"(
        The particles will be generated with the desired number density uniformly at random in all the domain.
        These IC may be used with any Particle Vector, but only make sense for regular PV.
            
    )")
        .def(py::init<float>(), "density"_a, R"(
            Args:
                density: target density
        )");

    py::handlers_class<UniformFilteredIC>(m, "UniformFiltered", pyic, R"(
        The particles will be generated with the desired number density uniformly at random in all the domain and then filtered out by the given filter.
        These IC may be used with any Particle Vector, but only make sense for regular PV.            
    )")
        .def(py::init<float, std::function<bool(PyTypes::float3)>>(),
             "density"_a, "filter"_a, R"(
            Args:
                density: target density
                filter: given position, returns True if the particle should be kept 
        )");

    py::handlers_class<UniformSphereIC>(m, "UniformSphere", pyic, R"(
        The particles will be generated with the desired number density uniformly at random inside or outside a given sphere.
        These IC may be used with any Particle Vector, but only make sense for regular PV.
            
    )")
        .def(py::init<float, PyTypes::float3, float, bool>(),
             "density"_a, "center"_a, "radius"_a, "inside"_a, R"(
            Args:
                density: target density
                center: center of the sphere
                radius: radius of the sphere
                inside: whether the particles should be inside or outside the sphere
        )");
}
