#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include <core/pvs/particle_vector.h>
#include <core/pvs/object_vector.h>
#include <core/mesh.h>
#include <core/pvs/rigid_object_vector.h>
#include <core/pvs/rigid_ellipsoid_object_vector.h>
#include <core/pvs/membrane_vector.h>

#include <core/utils/pytypes.h>

#include "nodelete.h"

namespace py = pybind11;
using namespace pybind11::literals;

void exportParticleVectors(py::module& m)
{
    // Particle Vectors
    py::nodelete_class<ParticleVector> pypv(m, "ParticleVector");
    pypv.def(py::init<std::string, float>(), "name"_a, "mass"_a)
        //
        .def("getCoordinates", &ParticleVector::getCoordinates_vector)
        .def("getVelocities",  &ParticleVector::getVelocities_vector)
        .def("getForces",      &ParticleVector::getForces_vector)
        //
        .def("setCoordinates", &ParticleVector::setCoordinates_vector)
        .def("setVelocities",  &ParticleVector::setVelocities_vector)
        .def("setForces",      &ParticleVector::setForces_vector);

    py::nodelete_class<Mesh> pymesh(m, "Mesh");
    pymesh.def(py::init<std::string>(), "off_filename"_a);

    py::nodelete_class<MembraneMesh>(m, "MembraneMesh", pymesh)
        .def(py::init<std::string>(), "off_filename"_a);
        
    py::nodelete_class<ObjectVector> (m, "ObjectVector", pypv)
        .def(py::init<std::string, float, int>(), "name"_a, "mass"_a, "object_size"_a);  
        
    py::nodelete_class<RigidObjectVector> (m, "RigidObjectVector", pypv)
        .def(py::init<std::string, float, pyfloat3, int, Mesh*>(),
             "name"_a, "mass"_a, "inertia"_a, "object_size"_a, "mesh"_a);
        
    py::nodelete_class<RigidEllipsoidObjectVector> (m, "RigidEllipsoidObjectVector", pypv)
        .def(py::init<std::string, float, int, pyfloat3>(),
             "name"_a, "mass"_a, "object_size"_a, "axes"_a);
}
