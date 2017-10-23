#include "object_forces_reverse_exchanger.h"

#include "object_halo_exchanger.h"

#include <core/utils/kernel_launch.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/rigid_object_vector.h>
#include <core/logger.h>
#include <core/utils/cuda_common.h>


__device__ __forceinline__ void atomicAddNonZero(float4* dest, float3 v)
{
	const float tol = 1e-7;

	float* fdest = (float*)dest;
	if (fabs(v.x) > tol) atomicAdd(fdest,     v.x);
	if (fabs(v.y) > tol) atomicAdd(fdest + 1, v.y);
	if (fabs(v.z) > tol) atomicAdd(fdest + 2, v.z);
}

__global__ void addHaloForces(
		const float4* recvForces, const int* origins,
		float4* forces, int objSize, int packedObjSize)
{
	const int objId = blockIdx.x;

	for (int pid = threadIdx.x; pid < objSize; pid += blockDim.x)
	{
		const int dstId = origins[objId*objSize + pid];
		Float3_int extraFrc( recvForces[objId*packedObjSize + pid] );
	
		atomicAddNonZero(forces + dstId, extraFrc.v);
	}
}

__global__ void addRigidForces(
		const float4* recvForces, const int* origins,
		ROVview view, int packedObjSize)
{
	const int objId = blockIdx.x;

	const int dstObjId = origins[objId*view.objSize] / view.objSize;

	if (threadIdx.x < 2)
	{
		float4 v = recvForces[ objId*packedObjSize + view.objSize + threadIdx.x ];

		if (threadIdx.x == 0)
			atomicAdd(&view.motions[dstObjId].force,  make_float3(v));

		if (threadIdx.x == 1)
			atomicAdd(&view.motions[dstObjId].torque, make_float3(v));
	}
}

__global__ void packRigidForces(ROVview view, float4* output, int packedObjSize)
{
	const int objId = blockIdx.x;

	for (int pid = threadIdx.x; pid < view.objSize; pid += blockDim.x)
		output[objId*view.objSize + pid] = view.forces[objId*view.objSize + pid];

	if (threadIdx.x == 0)
		output[objId*packedObjSize + view.objSize + 0] = make_float4(view.motions[objId].force,  0);

	if (threadIdx.x == 1)
		output[objId*packedObjSize + view.objSize + 1] = make_float4(view.motions[objId].torque, 0);
}


//===============================================================================================
// Member functions
//===============================================================================================

bool ObjectForcesReverseExchanger::needExchange(int id)
{
	return true;
}

void ObjectForcesReverseExchanger::attach(ObjectVector* ov)
{
	objects.push_back(ov);

	int psize = ov->objSize;
	if (dynamic_cast<RigidObjectVector*>(ov) != 0)
		psize += 2;

	ExchangeHelper* helper = new ExchangeHelper(ov->name, psize*sizeof(float4));
	helpers.push_back(helper);
}


void ObjectForcesReverseExchanger::prepareData(int id, cudaStream_t stream)
{
	auto ov = objects[id];
	auto helper = helpers[id];
	auto& offsets = entangledHaloExchanger->getRecvOffsets(id);

	debug2("Preparing %s forces to sending back", ov->name.c_str());

	for (int i=0; i < helper->nBuffers; i++)
		helper->sendSizes[i] = offsets[i+1] - offsets[i];

	helper->makeSendOffsets();
	helper->resizeSendBuf();

	auto rov = dynamic_cast<RigidObjectVector*>(ov);
	if (rov != nullptr)
	{
		int psize = rov->objSize + 2;
		ROVview view(rov, rov->halo());

		const int nthreads = 128;
		SAFE_KERNEL_LAUNCH(
				packRigidForces,
				view.nObjects, nthreads, 0, stream,
				view, (float4*)helper->sendBuf.devPtr(), psize);

	}
	else
	{
		CUDA_Check( cudaMemcpyAsync( helper->sendBuf.devPtr(),
									 ov->halo()->forces.devPtr(),
									 helper->sendBuf.size(), cudaMemcpyDeviceToDevice, stream ) );
	}

	debug2("Will send back forces for %d objects", offsets[helper->nBuffers]);
}

void ObjectForcesReverseExchanger::combineAndUploadData(int id, cudaStream_t stream)
{
	auto ov = objects[id];
	auto helper = helpers[id];

	int totalRecvd = helper->recvOffsets[helper->nBuffers];
	auto& origins = entangledHaloExchanger->getOrigins(id);

	debug("Updating forces for %d %s objects", totalRecvd, ov->name.c_str());

	int psize = ov->objSize;
	auto rov = dynamic_cast<RigidObjectVector*>(ov);
	if (rov != nullptr) psize += 2;

	const int nthreads = 128;
	SAFE_KERNEL_LAUNCH(
			addHaloForces,
			totalRecvd, nthreads, 0, stream,
			(const float4*)helper->recvBuf.devPtr(),     /* source */
			(const int*)origins.devPtr(),                /* destination ids here */
			(float4*)ov->local()->forces.devPtr(),       /* add to */
			ov->objSize, psize );

	if (rov != nullptr)
	{
		ROVview view(rov, rov->local());
		SAFE_KERNEL_LAUNCH(
				addRigidForces,
				totalRecvd, nthreads, 0, stream,
				(const float4*)helper->recvBuf.devPtr(),     /* source */
				(const int*)origins.devPtr(),                /* destination ids here */
				view, psize );                               /* add to, packed size */
	}
}





