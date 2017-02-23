#include <core/simulation.h>
#include <plugins/plugin.h>
#include <plugins/stats.h>
#include <plugins/dumpavg.h>
#include <core/xml/pugixml.hpp>
#include <core/wall.h>

Logger logger;

int main(int argc, char** argv)
{
	pugi::xml_document config;
	pugi::xml_parse_result result = config.load_file("poiseuille.xml");

	float3 globalDomainSize = config.child("simulation").child("domain").attribute("size").as_float3({32, 32, 32});
	int3 nranks3D{1, 2, 1};
	uDeviceX udevice(argc, argv, nranks3D, globalDomainSize, logger, "poiseuille.log", 9, false);

	SimulationPlugin  *simStat,  *simAvg;
	PostprocessPlugin *postStat, *postAvg;
	if (udevice.isComputeTask())
	{
		Integrator  constDP = createIntegrator(config.child("simulation").child("integrator"));
		Interaction dpdInt = createInteraction(config.child("simulation").child("interaction"));
		InitialConditions dpdIc = createIC(config.child("simulation").child("particle_vector"));
		Wall wall = createWall(config.child("simulation").child("wall"));

		ParticleVector* dpd = new ParticleVector(config.child("simulation").child("particle_vector").attribute("name").as_string());

		udevice.sim->registerParticleVector(dpd, &dpdIc);

		udevice.sim->registerIntegrator(&constDP);
		udevice.sim->registerInteraction(&dpdInt);
		udevice.sim->registerWall(&wall);

		udevice.sim->setIntegrator("dpd", "const_dp");
		udevice.sim->setInteraction("dpd", "dpd", "dpd_int");

		simStat = new SimulationStats("stats", 500);
		simAvg  = new Avg3DPlugin("averaging", "dpd", 10, 500, {24, 12, 24}, true, true, true);
	}
	else
	{
		postStat = new PostprocessStats("stats");
		postAvg = new Avg3DDumper("averaging", "xdmf/avgfields", nranks3D);
	}

	udevice.registerJointPlugins(simStat, postStat);
	udevice.registerJointPlugins(simAvg,  postAvg);
	udevice.run();

	return 0;
}
