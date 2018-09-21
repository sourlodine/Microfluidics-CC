#pragma once

#include <vector>
#include <string>
#include <mpi.h>
#include <core/domain.h>

#include <cuda_runtime.h>

class SDF_basedWall;
class ParticleVector;

void freezeParticlesInWall(SDF_basedWall *wall, ParticleVector *pv, float minVal=0.0f, float maxVal=1.2f);
void freezeParticlesInWalls(std::vector<SDF_basedWall*> walls, ParticleVector *pv, float minVal, float maxVal);

void dumpWalls2XDMF(std::vector<SDF_basedWall*> walls, float3 gridH, DomainInfo domain, std::string filename, MPI_Comm cartComm);
