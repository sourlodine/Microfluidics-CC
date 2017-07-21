/*
 * bounce.cu
 *
 *  Created on: Jul 20, 2017
 *      Author: alexeedm
 */

#include <core/bounce.h>
#include <core/particle_vector.h>
#include <core/celllist.h>
#include <core/rigid_object_vector.h>
#include <core/rigid_kernels/bounce.h>


void bounceFromRigidEllipsoid(ParticleVector* pv, CellList* cl, RigidObjectVector* rov, const float dt, bool local)
{
	debug("Bouncing %s particles from %s objects\n", pv->name.c_str(), rov->name.c_str());
	auto activeROV = local ? rov->local() : rov->halo();

	bounceEllipsoid<<< activeROV->nObjects, 128 >>> (
			(float4*)pv->local()->coosvels.devPtr(), pv->mass, activeROV->comAndExtents.devPtr(), activeROV->motions.devPtr(),
			activeROV->nObjects, 1.0f / rov->axes,
			cl->cellsStartSize.devPtr(), cl->cellInfo(), dt);
}
