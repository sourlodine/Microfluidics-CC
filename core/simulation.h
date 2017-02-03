#pragma once

#include <core/datatypes.h>
#include <core/containers.h>
#include <core/components.h>
#include <core/celllist.h>
#include <core/wall.h>
#include <plugins/plugin.h>

#include <vector>
#include <string>
#include <unordered_map>

class Simulation
{
	int3 nranks3D;
	int rank;
	int3 rank3D;
	float3 globalDomainSize, subDomainSize, subDomainStart;
	MPI_Comm cartComm;
	MPI_Comm& interComm;

private:

	std::unordered_map<std::string, int> pvMap;
	std::unordered_map<std::string, Interaction*> interactionMap;
	std::unordered_map<std::string, Integrator*>  integratorMap;
	std::unordered_map<std::string, Wall*>        wallMap;

	std::vector<ParticleVector*> particleVectors;
	std::vector<Interaction*>    interactions;
	std::vector<Integrator*>     integrators;
	std::vector<CellList*>       cellLists;

	std::vector<std::vector<CellList*>> cellListTable;
	std::vector<std::vector< std::pair<Interaction*, CellList*> >> interactionTable;

	std::vector<SimulationPlugin*> plugins;

public:
	Simulation(int3 nranks3D, float3 globalDomainSize, MPI_Comm& comm, MPI_Comm& interComm);

	void registerParticleVector(ParticleVector* pv, InitialConditions* ic);
	void registerObjectVector  (ObjectVector* ov);
	void registerWall          (Wall* wall);

	void registerInteraction   (Interaction* interaction);
	void registerIntegrator    (Integrator* integrator);

	void setIntegrator (std::string pvName, std::string integratorName);
	void setInteraction(std::string pv1Name, std::string pv2Name, std::string interactionName);

	void registerPlugin(SimulationPlugin* plugin);

	void run(int nsteps);

	const std::unordered_map<std::string, int>&   getPvMap() const { return pvMap; }
	const std::vector<ParticleVector*>& getParticleVectors() const { return particleVectors; }
};

class Postprocess
{
private:
	MPI_Comm& comm;
	MPI_Comm& interComm;
	std::vector<PostprocessPlugin*> plugins;
	std::vector<MPI_Request> requests;

public:
	Postprocess(MPI_Comm& comm, MPI_Comm& interComm);
	void registerPlugin(PostprocessPlugin* plugin);
	void run();
};

class uDeviceX
{
	int pluginId = 0;
	int computeTask;

public:
	Simulation* sim;
	Postprocess* post;

	uDeviceX(int argc, char** argv, int3 nranks3D, float3 globalDomainSize, Logger& logger, std::string logFileName, int verbosity=3);
	bool isComputeTask();
	void registerJointPlugins(SimulationPlugin* simPl, PostprocessPlugin* postPl);
	void run();
};
