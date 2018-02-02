#pragma once

#include "interface.h"

#include <core/containers.h>

class RigidObjectVector;


/**
 * Implements bounce-back from deformable mesh.
 * Mesh vertices must be the particles in the ParicleVector
 */
class BounceFromMesh : public Bouncer
{
public:
	BounceFromMesh(std::string name, float kbT);

	~BounceFromMesh() = default;

private:
	template<typename T>
	struct CollisionTableWrapper
	{
		PinnedBuffer<int> nCollisions{1};
		DeviceBuffer<T> collisionTable;
	};

	/**
	 * Maximum supported number of collisions per step
	 * will be #bouncesPerTri * total number of triangles in mesh
	 */
	const float collisionsPerTri  = 10.0f;
	const float collisionsPerEdge = 0.1f;

	CollisionTableWrapper<int2> triangleTable;
	CollisionTableWrapper<int3> edgeTable;
	DeviceBuffer<int> collisionTimes;

	float kbT;

	RigidObjectVector* rov;

	void exec(ParticleVector* pv, CellList* cl, float dt, bool local, cudaStream_t stream) override;
	void setup(ObjectVector* ov) override;
};
