#pragma once

#include <string>
#include <core/datatypes.h>
#include <core/particle_vector.h>

class CellList;

struct ObjectVector: public ParticleVector
{
	struct __align__(16) Properties
	{
		float3 com, low, high;
	};


	int nObjects = 0;
	int objSize  = 0;
	DeviceBuffer<int> particles2objIds;
	DeviceBuffer<Properties> properties;

	PinnedBuffer<Force> haloForces;
	DeviceBuffer<int>   haloIds;

	ObjectVector(std::string name, const int objSize, const int nObjects = 0) :
		ParticleVector(name, objSize*nObjects), objSize(objSize), nObjects(nObjects)
	{
		resize(nObjects*objSize, ResizeKind::resizeAnew);
	};

	virtual void pushStreamWOhalo(cudaStream_t stream)
	{
		ParticleVector::pushStreamWOhalo(stream);

		particles2objIds.pushStream(stream);
		properties.		 pushStream(stream);
	}

	virtual void popStreamWOhalo()
	{
		ParticleVector::popStreamWOhalo();

		particles2objIds.popStream();
		properties.		 popStream();
	}

	virtual void resize(const int np, ResizeKind kind = ResizeKind::resizePreserve)
	{
		if (np % objSize != 0)
			die("Incorrect number of %s particles", name.c_str());

		nObjects = np / objSize;

		ParticleVector::resize(nObjects * objSize, kind);
		particles2objIds.resize(np, kind);
		properties.resize(nObjects);
	}

	virtual ~ObjectVector() = default;

	void findExtentAndCOM(cudaStream_t stream);
};
