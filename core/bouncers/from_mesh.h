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

protected:
	float kbT;

	/**
	 * Maximum supported number of collisions per step
	 * will be #bouncesPerTri * total number of triangles in mesh
	 */
	static const int bouncesPerTri = 1;

	PinnedBuffer<int> nCollisions;

	/**
	 * Collision table and sorted collision table.
	 * First integer is the colliding particle id, second is triangle id
	 */
	DeviceBuffer<int2> collisionTable, tmp_collisionTable;
	DeviceBuffer<char> sortBuffer;

	RigidObjectVector* rov;

	void exec(ParticleVector* pv, CellList* cl, float dt, bool local, cudaStream_t stream) override;
	void setup(ObjectVector* ov) override;
};
