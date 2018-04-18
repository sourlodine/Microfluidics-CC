//================================================================================================
// Bouncers
//================================================================================================

#pragma once

#include <core/xml/pugixml.hpp>

#include <core/bouncers/from_mesh.h>
#include <core/bouncers/from_ellipsoid.h>

#include <core/utils/make_unique.h>

class BouncerFactory
{
private:
	static std::unique_ptr<Bouncer> createMeshBouncer(pugi::xml_node node)
	{
		auto name = node.attribute("name").as_string("");
		auto kbT  = node.attribute("kbt").as_float(0.5f);

		return std::make_unique<BounceFromMesh>(name, kbT);
	}

	static std::unique_ptr<Bouncer> createEllipsoidBouncer(pugi::xml_node node)
	{
		auto name = node.attribute("name").as_string("");

		return std::make_unique<BounceFromRigidEllipsoid>(name);
	}

public:
	static std::unique_ptr<Bouncer> create(pugi::xml_node node)
	{
		std::string type = node.attribute("type").as_string();

		if (type == "from_mesh")
			return createMeshBouncer(node);

		if (type == "from_ellipsoids")
			return createEllipsoidBouncer(node);

		die("Unable to parse input at %s, unknown 'type': '%s'", node.path().c_str(), type.c_str());

		return nullptr;
	}
};
