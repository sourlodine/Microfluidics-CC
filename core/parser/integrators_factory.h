//================================================================================================
// Integrators
//================================================================================================

#pragma once

#include <core/xml/pugixml.hpp>
#include <core/utils/make_unique.h>

#include <core/integrators/vv.h>
#include <core/integrators/const_omega.h>
#include <core/integrators/oscillate.h>
#include <core/integrators/translate.h>
#include <core/integrators/rigid_vv.h>

#include <core/integrators/forcing_terms/none.h>
#include <core/integrators/forcing_terms/const_dp.h>
#include <core/integrators/forcing_terms/periodic_poiseuille.h>

class IntegratorFactory
{
private:
	static std::unique_ptr<Integrator> createVV(pugi::xml_node node)
	{
		auto name = node.attribute("name").as_string();
		auto dt   = node.attribute("dt").as_float(0.01);

		Forcing_None forcing;

		return  std::make_unique<IntegratorVV<Forcing_None>>(name, dt, forcing);
	}

	static std::unique_ptr<Integrator> createVV_constDP(pugi::xml_node node)
	{
		auto name       = node.attribute("name").as_string();
		auto dt         = node.attribute("dt").as_float(0.01);

		auto extraForce = node.attribute("extra_force").as_float3();

		Forcing_ConstDP forcing(extraForce);

		return  std::make_unique<IntegratorVV<Forcing_ConstDP>>(name, dt, forcing);
	}

	static std::unique_ptr<Integrator> createVV_PeriodicPoiseuille(pugi::xml_node node)
	{
		auto name  = node.attribute("name").as_string();
		auto dt    = node.attribute("dt").as_float(0.01);

		auto force = node.attribute("force").as_float(0);

		std::string dirStr = node.attribute("direction").as_string("x");

		Forcing_PeriodicPoiseuille::Direction dir;
		if (dirStr == "x") dir = Forcing_PeriodicPoiseuille::Direction::x;
		if (dirStr == "y") dir = Forcing_PeriodicPoiseuille::Direction::y;
		if (dirStr == "z") dir = Forcing_PeriodicPoiseuille::Direction::z;

		Forcing_PeriodicPoiseuille forcing(force, dir);

		return  std::make_unique<IntegratorVV<Forcing_PeriodicPoiseuille>>(name, dt, forcing);
	}

	static std::unique_ptr<Integrator> createConstOmega(pugi::xml_node node)
	{
		auto name   = node.attribute("name").as_string();
		auto dt     = node.attribute("dt").as_float(0.01);

		auto center = node.attribute("center").as_float3();
		auto omega  = node.attribute("omega") .as_float3();

		return  std::make_unique<IntegratorConstOmega>(name, dt, center, omega);
	}

	static std::unique_ptr<Integrator> createTranslate(pugi::xml_node node)
	{
		auto name   = node.attribute("name").as_string();
		auto dt     = node.attribute("dt").as_float(0.01);

		auto vel   = node.attribute("velocity").as_float3();

		return  std::make_unique<IntegratorTranslate>(name, dt, vel);
	}

	static std::unique_ptr<Integrator> createOscillating(pugi::xml_node node)
	{
		auto name    = node.attribute("name").as_string();
		auto dt      = node.attribute("dt").as_float(0.01);

		auto vel     = node.attribute("velocity").as_float3();
		auto period  = node.attribute("period").as_float();

		return  std::make_unique<IntegratorOscillate>(name, dt, vel, period);
	}

	static std::unique_ptr<Integrator> createRigidVV(pugi::xml_node node)
	{
		auto name = node.attribute("name").as_string();
		auto dt   = node.attribute("dt").as_float(0.01);

		return  std::make_unique<IntegratorVVRigid>(name, dt);
	}

public:
	static std::unique_ptr<Integrator> create(pugi::xml_node node)
	{
		std::string type = node.attribute("type").as_string();

		if (type == "vv")
			return createVV(node);
		if (type == "vv_const_dp")
			return createVV_constDP(node);
		if (type == "vv_periodic_poiseuille")
			return createVV_PeriodicPoiseuille(node);
		if (type == "const_omega")
			return createConstOmega(node);
		if (type == "oscillate")
			return createOscillating(node);
		if (type == "translate")
			return createTranslate(node);
		if (type == "rigid_vv")
			return createRigidVV(node);

		die("Unable to parse input at %s, unknown 'type': '%s'", node.path().c_str(), type.c_str());

		return nullptr;
	}
};
