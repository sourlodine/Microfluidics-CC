#include <extern/pybind11/include/pybind11/pybind11.h>
#include <extern/pybind11/include/pybind11/stl.h>

#include <core/pvs/particle_vector.h>
#include <core/pvs/object_vector.h>
#include <core/mesh.h>
#include <core/pvs/rigid_object_vector.h>
#include <core/pvs/rigid_ellipsoid_object_vector.h>
#include <core/pvs/membrane_vector.h>

namespace py = pybind11;
using namespace pybind11::literals;

void exportParticleVectors(py::module& m)
{
    // Particle Vectors
    py::class_<ParticleVector> pypv(m, "ParticleVector");
    pypv.def(py::init<std::string, float>(), "name"_a, "mass"_a)
        //
        .def("getCoordinates", &ParticleVector::getCoordinates_vector)
        .def("getVelocities",  &ParticleVector::getVelocities_vector)
        .def("getForces",      &ParticleVector::getForces_vector)
        //
        .def("setCoordinates", &ParticleVector::setCoordinates_vector)
        .def("setVelocities",  &ParticleVector::setVelocities_vector)
        .def("setForces",      &ParticleVector::setForces_vector);

    py::class_<Mesh> pymesh(m, "Mesh");
    pymesh.def(py::init<std::string>(), "off_filename"_a);

    py::class_<MembraneMesh>(m, "MembraneMesh", pymesh)
        .def(py::init<std::string>(), "off_filename"_a);
        
    py::class_<ObjectVector> (m, "ObjectVector", pypv)
        .def(py::init<std::string, float, int>(), "name"_a, "mass"_a, "object_size"_a);  
        
    py::class_<RigidObjectVector> (m, "RigidObjectVector", pypv)
        .def(py::init<std::string, float, pyfloat3, int, std::unique_ptr<Mesh>>(),
             "name"_a, "mass"_a, "inertia"_a, "object_size"_a, "mesh"_a);
}
