/*
 * bounce.cu
 *
 *  Created on: Jul 20, 2017
 *      Author: alexeedm
 */

#include "from_ellipsoid.h"

#include <core/utils/kernel_launch.h>
#include <core/celllist.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/rigid_ellipsoid_object_vector.h>

#include <core/rigid_kernels/bounce.h>
#include <core/rigid_kernels/integration.h>


void BounceFromRigidEllipsoid::exec(ParticleVector* pv, CellList* cl, float dt, cudaStream_t stream, bool local)
{
	auto reov = dynamic_cast<RigidEllipsoidObjectVector*>(ov);
	if (reov == nullptr)
		die("Analytic ellispoid bounce only works with RigidObjectVector");

	debug("Bouncing %s particles from %s object vector", pv->name.c_str(), reov->name.c_str());

	REOVview_withOldMotion ovView(reov, local ? reov->local() : reov->halo());
	PVview_withOldParticles pvView(pv, pv->local());

	int nthreads = 256;
	if (!local)
	{
		SAFE_KERNEL_LAUNCH(
				clearRigidForces,
				getNblocks(ovView.nObjects, 64), 64, 0, stream,
				ovView );
	}

	SAFE_KERNEL_LAUNCH(
			bounceEllipsoid,
			ovView.nObjects, nthreads, 2*nthreads*sizeof(int), stream,
			ovView, pvView, cl->cellInfo(), dt );
}



