#pragma once

#include <core/containers.h>
#include <core/datatypes.h>
#include "object_vector.h"


class LocalRBCvector : public LocalObjectVector
{
public:
	LocalRBCvector(const int rbcSize, const int nRbcs = 0, cudaStream_t stream = 0) :
		LocalObjectVector(rbcSize, nRbcs)
	{
		dataPerObject["area_volumes"] = std::unique_ptr<GPUcontainer> (new PinnedBuffer<float2>(nObjects));
	}

	virtual ~LocalRBCvector() = default;
};

class RBCvector : public ObjectVector
{
public:
	RBCvector(std::string name, float mass, const int objSize, /*ObjectMesh mesh,*/ const int nObjects = 0) :
		ObjectVector( name, mass, objSize,
					  new LocalRBCvector(objSize, nObjects),
					  new LocalRBCvector(objSize, 0) )
	{
		// FIXME shit is everywhere
		//this->mesh = mesh;
	}

	LocalRBCvector* local() { return static_cast<LocalRBCvector*>(_local); }
	LocalRBCvector* halo()  { return static_cast<LocalRBCvector*>(_halo);  }

	virtual ~RBCvector() {};
};
