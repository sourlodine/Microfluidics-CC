#include <string>
#include <utility>
#include <regex>
#include <fstream>

#include <core/simulation.h>
#include "freeze_particles.h"

#include <core/interactions/pairwise.h>
#include <core/interactions/pairwise_interactions/dpd.h>

#include <core/initial_conditions/uniform_ic.h>

#include <core/integrators/forcing_terms/none.h>
#include <core/integrators/vv.h>

#include <core/argument_parser.h>
#include <core/pvs/particle_vector.h>
#include <core/utils/kernel_launch.h>
#include <core/parser/walls_factory.h>

#include <core/utils/make_unique.h>


__global__ void zeroVels(PVview view)
{
	const int pid = threadIdx.x + blockDim.x * blockIdx.x;
	if (pid >= view.size) return;

	view.particles[2*pid+1] = make_float4(0);
}

Logger logger;

void writeXYZ(MPI_Comm comm, std::string fname, ParticleVector* pv)
{
	int rank;
	MPI_Check( MPI_Comm_rank(comm, &rank) );

	int dims[3], periods[3], coords[3];
	MPI_Check( MPI_Cart_get(comm, 3, dims, periods, coords) );

	const int nlocal = pv->local()->size();
	int n = nlocal;
	MPI_Check( MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &n, &n, 1, MPI_INT, MPI_SUM, 0, comm) );

	MPI_File f;
	MPI_Check( MPI_File_open(comm, fname.c_str(), MPI_MODE_CREATE|MPI_MODE_DELETE_ON_CLOSE|MPI_MODE_WRONLY, MPI_INFO_NULL, &f) );
	MPI_Check( MPI_File_close(&f) );
	MPI_Check( MPI_File_open(comm, fname.c_str(), MPI_MODE_WRONLY | MPI_MODE_CREATE, MPI_INFO_NULL, &f) );

	std::stringstream ss;
	ss.setf(std::ios::fixed, std::ios::floatfield);
	ss.precision(5);

	if (rank == 0)
	{
		ss <<  n << "\n";
		ss << pv->name << "\n";

		info("xyz dump of %s: total number of particles: %d", pv->name.c_str(), n);
	}

	pv->local()->coosvels.downloadFromDevice(0);
	for(int i = 0; i < nlocal; ++i)
	{
		Particle p = pv->local()->coosvels[i];
		p.r = pv->domain.local2global(p.r);

		ss << rank << " "
				<< std::setw(10) << p.r.x << " "
				<< std::setw(10) << p.r.y << " "
				<< std::setw(10) << p.r.z << "\n";
	}

	string content = ss.str();

	MPI_Offset len = content.size();
	MPI_Offset offset = 0;
	MPI_Check( MPI_Exscan(&len, &offset, 1, MPI_OFFSET, MPI_SUM, comm));

	MPI_Status status;
	MPI_Check( MPI_File_write_at_all(f, offset, content.c_str(), len, MPI_CHAR, &status) );
	MPI_Check( MPI_File_close(&f));
}

std::string subsVariables(const std::string& variables, const std::string& content)
{
	std::regex pattern(R"(([^\s,]+)\s*=\s*([^\s,]+))");
	std::smatch match;
	std::string result = content;

	auto searchStart = variables.cbegin();

	while ( std::regex_search( searchStart, variables.cend(), match, pattern ) )
	{
		auto varname = match[1].str();
		auto value   = match[2].str();

		searchStart += match.position() + match.length();

		// \$name\b|\$\{$name\}
		std::regex subs(R"(\$)" + varname + R"(\b|\$\{)" + varname + R"(\})");
		result = std::regex_replace(result, subs, value);
	}

	return result;
}

static std::unique_ptr<Interaction> createDPD(pugi::xml_node node, std::string pvname)
{
	auto name = node.attribute("name").as_string("int");
	auto rc   = node.attribute("rc").as_float(1.0f);

	auto gamma = node.attribute("gamma").as_float(1);
	auto dt    = node.attribute("dt")   .as_float(0.001);

	auto a     = node.attribute("a")    .as_float(50);
	auto kbT   = node.attribute("kbt")  .as_float(1.0);
	auto power = node.attribute("power").as_float(1.0f);

	Pairwise_DPD dpd(rc, a, gamma, kbT, dt, power);

	auto res = std::make_unique<InteractionPair<Pairwise_DPD>>(name, rc);
	
	res->createPairwise(pvname, pvname, dpd);

	return std::move(res);
}


int main(int argc, char** argv)
{
	srand48(4242);

	int rank;
	MPI_Init(&argc, &argv);
	MPI_Comm_rank(MPI_COMM_WORLD, &rank);

	std::string xmlname;
	int nsteps;
	bool needXYZ;
	std::string variables;
	int forceDebugLvl;

	{
		using namespace ArgumentParser;

		std::vector<OptionStruct> opts
		({
			{'i', "input",     STRING, "Input script",                            &xmlname,   std::string("script.xml")},
			{'e', "epochs",    INT,    "Number of timesteps",                     &nsteps,   50},
			{'x', "xyz",       BOOL,   "Also dump .xyz files",                    &needXYZ,   false},
			{'d', "debug",     INT,    "Override debug level, "
									   "from 1 (lowest) to 9 (highest)",          &forceDebugLvl, -1},

			{'v', "variables", STRING, "Comma-separated list of variables and "
								       "their values that will be substituted "
								       "into the input script with format: "
								       "'var1=value1,var2=value2, var3=value3'",  &variables,     std::string("")},
		});

		ArgumentParser::Parser parser(opts, rank == 0);
		parser.parse(argc, argv);
	}


	// Read the file into memory
	std::ifstream f(xmlname);
	if (!f.good()) // Can't die here, logger is not yet setup
	{
		fprintf(stderr, "Couldn't open script file (not found or not accessible)\n");
		exit(1);
	}

	std::stringstream buffer;
	buffer << f.rdbuf();

	// And substitute the variables
	pugi::xml_document config;
	auto result = config.load( subsVariables(variables, buffer.str()).c_str() );
	if (!result)
	{
		fprintf(stderr, "Couldn't open script file, xml parser says: \"%s\"\n", result.description());
		exit(1);
	}

	if (forceDebugLvl >= 0)
		logger.init(MPI_COMM_WORLD, "genwall.log", forceDebugLvl);
	else
		logger.init(MPI_COMM_WORLD, "genwall.log", config.child("simulation").attribute("debug_lvl").as_int(3));


	// Write the script that we actually execute (with substitutions)
	if (rank == 0)
	{
		config.save_file("uDeviceX_genwall_script.xml");
	}


	float3 globalDomainSize = config.child("simulation").child("domain").attribute("size").as_float3({32, 32, 32});
	int3 nranks3D = config.child("simulation").attribute("mpi_ranks").as_int3({1, 1, 1});

	auto genOne = [=] (pugi::xml_node wallNode, pugi::xml_node wallGenNode) {

		if (wallGenNode.type() == pugi::node_null)
			die("Wall %s has no generation instructions", wallNode.attribute("name").as_string());

		info("Generating wall %s", wallNode.attribute("name").as_string());


		auto sim = std::make_unique<Simulation>(nranks3D, globalDomainSize, MPI_COMM_WORLD, MPI_COMM_NULL, false);

		std::string wname = wallNode.attribute("name").as_string("");

		auto startingPV = std::make_unique<ParticleVector>             (wname, 1.0);
		auto final      = std::make_unique<ParticleVector>             (wname, 1.0);
		auto ic         = std::make_unique<UniformIC>                  (wallGenNode.attribute("density").as_float(4));
		auto vv         = std::make_unique<IntegratorVV<Forcing_None>> ("vv", wallGenNode.attribute("dt").as_float(0.001), Forcing_None());

		auto startingPtr = startingPV.get();
		auto finalPtr    = final.get();

		// Create and setup wall
		auto wall = WallFactory::create(wallNode);
		auto wallPtr = wall.get();
		sim->registerWall(std::move(wall));

		// Make a new particle vector uniformly everywhere
		sim->registerParticleVector(std::move(startingPV), std::move(ic), 0);

		// Interaction
		auto dpd = createDPD(wallGenNode, wname);
		auto dpdPtr = dpd.get();

		sim->registerInteraction(std::move(dpd));
		sim->setInteraction(dpdPtr->name, wname, wname);
		sim->registerIntegrator(std::move(vv));
		sim->setIntegrator("vv", wname);

		sim->init();
		sim->run(nsteps);

		auto sdfWall = dynamic_cast<SDF_basedWall*>(wallPtr);
		if (sdfWall == nullptr)
			die("Only sdf-based walls are supported for now");

		freezeParticlesInWall(sdfWall, startingPtr, finalPtr, 0, 1.2);

		if (needXYZ)
		{
			writeXYZ(sim->getCartComm(), wname+"_unfiltered.xyz", startingPtr);
			writeXYZ(sim->getCartComm(), finalPtr->name+".xyz", finalPtr);
		}

		std::string path = wallGenNode.attribute("path").as_string("./");
		std::string command = "mkdir -p " + path;
		if (rank == 0)
		{
			if ( system(command.c_str()) != 0 )
				die("Could not create folders by given path %s", path.c_str());
		}

		PVview view(finalPtr, finalPtr->local());
		const int nthreads = 128;
		SAFE_KERNEL_LAUNCH( zeroVels,
				getNblocks(view.size, nthreads), nthreads, 0, 0,
				view);

		final->checkpoint(sim->getCartComm(), path);

		sim->finalize();
	};

	for (auto node : config.child("simulation").children("wall"))
	{
		genOne(node, node.child("generate_frozen"));
	}
}
