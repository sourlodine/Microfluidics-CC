#pragma once

#include "object_vector.h"

#include <core/rigid_kernels/rigid_motion.h>

class LocalRigidObjectVector : public LocalObjectVector
{
public:
	LocalRigidObjectVector(ParticleVector* pv, const int objSize, const int nObjects = 0) :
		LocalObjectVector(pv, objSize, nObjects)
	{	}

	PinnedBuffer<Particle>* getMeshVertices(cudaStream_t stream) override;
	PinnedBuffer<Particle>* getOldMeshVertices(cudaStream_t stream) override;
	DeviceBuffer<Force>* getMeshForces(cudaStream_t stream) override;

protected:
	PinnedBuffer<Particle> meshVertices;
	PinnedBuffer<Particle> meshOldVertices;
	DeviceBuffer<Force>    meshForces;
};

class RigidObjectVector : public ObjectVector
{
public:
	PinnedBuffer<float4> initialPositions;

	/// Diagonal of the inertia tensor in the principal axes
	/// The axes should be aligned with ox, oy, oz when q = {1 0 0 0}
	float3 J;

	RigidObjectVector(std::string name, float partMass, float3 J, const int objSize, std::unique_ptr<Mesh> mesh, const int nObjects = 0) :
		ObjectVector( name, partMass, objSize,
					  new LocalRigidObjectVector(this, objSize, nObjects),
					  new LocalRigidObjectVector(this, objSize, 0) ),
					  J(J)
	{
		this->mesh = std::move(mesh);

		if (length(J) < 1e-5)
			die("Wrong momentum of inertia: [%f %f %f]", J.x, J.y, J.z);

		// rigid motion must be exchanged and shifted
		requireDataPerObject<RigidMotion>("motions", true, sizeof(RigidReal));
	}

	LocalRigidObjectVector* local() { return static_cast<LocalRigidObjectVector*>(_local); }
	LocalRigidObjectVector* halo()  { return static_cast<LocalRigidObjectVector*>(_halo);  }

	virtual ~RigidObjectVector() = default;
};

#include "views/rov.h"



