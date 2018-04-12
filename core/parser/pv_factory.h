//================================================================================================
// Particle vectors
//================================================================================================

#pragma once

#include <core/xml/pugixml.hpp>
#include <core/utils/make_unique.h>

#include <core/pvs/particle_vector.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/rigid_object_vector.h>
#include <core/pvs/rigid_ellipsoid_object_vector.h>
#include <core/pvs/rbc_vector.h>

#include <core/mesh.h>

class ParticleVectorFactory
{
private:
	static std::unique_ptr<ParticleVector> createRegularPV(pugi::xml_node node)
	{
		auto name = node.attribute("name").as_string();
		auto mass = node.attribute("mass").as_float(1.0);

		return std::make_unique<ParticleVector>(name, mass);
	}

	static std::unique_ptr<ParticleVector> createRigidEllipsoids(pugi::xml_node node)
	{
		auto name    = node.attribute("name").as_string("");
		auto mass    = node.attribute("mass").as_float(1);

		auto objSize = node.attribute("particles_per_obj").as_int(1);
		auto axes    = node.attribute("axes").as_float3( make_float3(1) );

		return std::make_unique<RigidEllipsoidObjectVector>(name, mass, objSize, axes);
	}

	static std::unique_ptr<ParticleVector> createRigidObjects(pugi::xml_node node)
	{
		auto name      = node.attribute("name").as_string("");
		auto mass      = node.attribute("mass").as_float(1);

		auto objSize   = node.attribute("particles_per_obj").as_int(1);
		auto J         = node.attribute("moment_of_inertia").as_float3();
		auto meshFname = node.attribute("mesh_filename").as_string("mesh.off");

		auto mesh = std::make_unique<Mesh>(meshFname);

		return std::make_unique<RigidObjectVector>(name, mass, J, objSize, std::move(mesh));
	}

	static std::unique_ptr<ParticleVector> createMembranes(pugi::xml_node node)
	{
		auto name      = node.attribute("name").as_string("");
		auto mass      = node.attribute("mass").as_float(1);

		auto objSize   = node.attribute("particles_per_obj").as_int(1);

		auto meshFname = node.attribute("mesh_filename").as_string("rbcmesh.off");

		auto mmesh = std::make_unique<MembraneMesh>(meshFname);

		return std::make_unique<RBCvector>(name, mass, objSize, std::move(mmesh));
	}

public:
	static std::unique_ptr<ParticleVector> create(pugi::xml_node node)
	{
		std::string type = node.attribute("type").as_string();

		if (type == "regular")
			return createRegularPV(node);
		if (type == "rigid_ellipsoids")
			return createRigidEllipsoids(node);
		if (type == "rigid_objects")
			return createRigidObjects(node);
		if (type == "membrane")
			return createMembranes(node);

		die("Unable to parse input at %s, unknown 'type': '%s'", node.path().c_str(), type.c_str());
		return nullptr;
	}
};
