#pragma once

#include <string>
#include <core/containers.h>
#include <core/datatypes.h>
#include <core/pvs/object_vector.h>


class LocalRBCvector : public LocalObjectVector
{
public:
	DeviceBuffer<float> volumes, areas;

	LocalRBCvector(const int rbcSize, const int nRbcs = 0, cudaStream_t stream = 0) :
		LocalObjectVector(rbcSize, nRbcs)
	{ }

	virtual void resize(const int np, cudaStream_t stream, ResizeKind kind = ResizeKind::resizePreserve)
	{
		LocalObjectVector::resize(np, stream, kind);
		areas.  resize(nObjects, stream, kind);
		volumes.resize(nObjects, stream, kind);
	}

	virtual ~LocalRBCvector() = default;
};

class RBCvector : public ObjectVector
{
public:
	struct Parameters
	{
		float kbT, p, lmax, q, Cq, totArea0, totVolume0, l0, ka, kv, gammaC, gammaT, kb;
		float kbToverp, cost0kb, sint0kb;
	};

	Parameters parameters;

	RBCvector(std::string name, const int objSize, const int nObjects = 0) :
		ObjectVector( name, objSize,
					  new LocalRBCvector(objSize, nObjects),
					  new LocalRBCvector(objSize, 0) )
	{}

	LocalRBCvector* local() { return static_cast<LocalRBCvector*>(_local); }
	LocalRBCvector* halo()  { return static_cast<LocalRBCvector*>(_halo);  }

	virtual ~RBCvector() {};
};
