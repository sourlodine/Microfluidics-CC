#include <core/pvs/particle_vector.h>
#include <core/pvs/object_vector.h>
#include <core/celllist.h>
#include <core/logger.h>
#include <core/cuda_common.h>

#include <core/mpi/object_redistributor.h>
#include <core/mpi/valid_cell.h>

#include <vector>
#include <algorithm>
#include <limits>



__device__ void packExtraData(int objId, int32_t** extraData, int nPtrsPerObj, const int* dataSizes, int32_t* destanation)
{
	int baseId = 0;

	for (int ptrId = 0; ptrId < nPtrsPerObj; ptrId++)
		{
			// dataSizes are in bytes
			const int size = dataSizes[ptrId] / 4;
			for (int i = threadIdx.x; i < size; i += blockDim.x)
				destanation[baseId+i] = extraData[ptrId][objId*size + i];

			baseId += dataSizes[ptrId];
		}
}

__device__ void unpackExtraData(int objId, int32_t** extraData, int nPtrsPerObj, const int* dataSizes, const int32_t* source)
{
	int baseId = 0;

	for (int ptrId = 0; ptrId < nPtrsPerObj; ptrId++)
	{
		// dataSizes are in bytes
		const int size = dataSizes[ptrId] / 4;
		for (int i = threadIdx.x; i < size; i += blockDim.x)
			extraData[ptrId][objId*size + i] = source[baseId+i];

		baseId += dataSizes[ptrId];
	}
}


__global__ void getExitingObjects(const float4* __restrict__ coosvels, const LocalObjectVector::COMandExtent* props, const int nObj, const int objSize,
		const float3 localDomainSize,
		const int64_t dests[27], int bufSizes[27], /*int* haloParticleIds,*/
		const int packedObjSize_byte, int32_t** extraData, int nPtrsPerObj, const int* dataSizes)
{
	const int objId = blockIdx.x;
	const int tid = threadIdx.x;
	const int sh  = tid % 2;

	if (objId >= nObj) return;

	// Find to which buffer this object should go
	auto prop = props[objId];
	int cx = 1, cy = 1, cz = 1;

	if (prop.com.x  < -0.5*localDomainSize.x) cx = 0;
	if (prop.com.y  < -0.5*localDomainSize.y) cy = 0;
	if (prop.com.z  < -0.5*localDomainSize.z) cz = 0;

	if (prop.com.x >=  0.5*localDomainSize.x) cx = 2;
	if (prop.com.y >=  0.5*localDomainSize.y) cy = 2;
	if (prop.com.z >=  0.5*localDomainSize.z) cz = 2;

//	if (tid == 0) printf("Obj %d : [%f %f %f] -- [%f %f %f]\n", objId,
//			prop.low.x, prop.low.y, prop.low.z, prop.high.x, prop.high.y, prop.high.z);


	const int bufId = (cz*3 + cy)*3 + cx;

	__shared__ int shDstObjId;

	const float3 shift{ localDomainSize.x*(cx-1),
						localDomainSize.y*(cy-1),
						localDomainSize.z*(cz-1) };

	__syncthreads();
	if (tid == 0)
		shDstObjId = atomicAdd(bufSizes + bufId, 1);
	__syncthreads();

//		if (tid == 0)
//			if (objId == 5)
//				printf("obj  %d  to halo  %d  [%f %f %f] - [%f %f %f]  %d %d %d\n", objId, bufId,
//						prop.low.x, prop.low.y, prop.low.z, prop.high.x, prop.high.y, prop.high.z, cx, cy, cz);

	float4* dstAddr = (float4*) (dests[bufId]) + packedObjSize_byte/sizeof(float4) * shDstObjId;

	for (int pid = tid/2; pid < objSize; pid += blockDim.x/2)
	{
		const int srcId = objId * objSize + pid;
		Float3_int data(coosvels[2*srcId + sh]);

		if (sh == 0) data.v -= shift;

		dstAddr[2*pid + sh] = data.toFloat4();
	}

	// Add extra data at the end of the object
	dstAddr += objSize*2;
	packExtraData(objId, extraData, nPtrsPerObj, dataSizes, (int32_t*)dstAddr);
}


__global__ void unpackObject(const float4* from, float4* to, const int objSize, const int packedObjSize_byte, const int nObj,
		int32_t** extraData, int nPtrsPerObj, const int* dataSizes)
{
	const int objId = blockIdx.x;
	const int tid = threadIdx.x;
	const int sh  = tid % 2;

	for (int pid = tid/2; pid < objSize; pid += blockDim.x/2)
	{
		const int srcId = objId * packedObjSize_byte/sizeof(float4) + pid*2;
		float4 data = from[srcId + sh];

		to[2*(objId*objSize + pid) + sh] = data;
	}

	unpackExtraData(objId, extraData, nPtrsPerObj, dataSizes, (int32_t*)( ((char*)from) + objId * packedObjSize_byte + objSize*sizeof(Particle) ));
}





void ObjectRedistributor::attach(ObjectVector* ov, float rc)
{
	objects.push_back(ov);

	const float objPerCell = 0.1f;

	const int maxdim = std::max({ov->localDomainSize.x, ov->localDomainSize.y, ov->localDomainSize.z});

	const int sizes[3] = { (int)(4*objPerCell * maxdim*maxdim + 10),
						   (int)(4*objPerCell * maxdim + 10),
						   (int)(4*objPerCell + 10) };


	ExchangeHelper* helper = new ExchangeHelper(ov->name, ov->local()->packedObjSize_bytes, sizes);

	//  Central buffer will be used to move the data around
	// while removing exiting objects
	helper->sendBufs[13].pushStream(stream);
	helper->sendBufs[13].resize( ov->local()->packedObjSize_bytes * (ov->local()->nObjects + 5) * 1.5 );
	helper->sendAddrs[13] = sendBufs[i].devPtr();
	helper->sendAddrs.uploadToDevice();

	ov->halo()->pushStream(helper->stream);
	helpers.push_back(helper);
}


void ObjectRedistributor::prepareData(int id)
{
	auto ov = objects[id];
	auto helper = helpers[id];

	debug2("Preparing %s halo on the device", ov->name.c_str());

	helper->bufSizes.pushStream(defStream);
	helper->bufSizes.clearDevice();

	if ( helper->sendBufs[13].size() < ov->local()->packedObjSize_bytes * ov->local()->nObjects )
	{
		helper->sendBufs[13].pushStream(stream);
		helper->sendBufs[13].resize( ov->local()->packedObjSize_bytes * ov->local()->nObjects * 1.5 );
		helper->sendAddrs[13] = sendBufs[i].devPtr();
		helper->sendAddrs.uploadToDevice();
	}

	const int nthreads = 128;
	if (ov->local()->nObjects > 0)
	{
		int       nPtrs  = ov->local()->extraDataPtrs.size();
		int totSize_byte = ov->local()->packedObjSize_bytes;

		getExitingObjects <<< ov->local()->nObjects, nthreads, 0, defStream >>> (
				(float4*)ov->local()->coosvels.devPtr(), ov->local()->comAndExtents.devPtr(),
				ov->local()->nObjects, ov->local()->objSize, ov->localDomainSize,
				(int64_t*)helper->sendAddrs.devPtr(), helper->bufSizes.devPtr(),
				totSize_byte, ov->local()->extraDataPtrs.devPtr(), nPtrs, ov->local()->extraDataSizes.devPtr());

		// Unpack the central buffer into the object vector itself
		helper->bufSizes.downloadFromDevice();
		int nObjs = helper->bufSizes[13];
		unpackObject<<< nObjs, nthreads, 0, defStream >>>
				(((float4*)helper->sendBufs[13].devPtr(), (float4*)ov->local()->coosvels.devPtr(), ov->local()->objSize, ov->local()->packedObjSize_bytes, nObjs,
				 ov->local()->extraDataPtrs.devPtr(), nPtrs, ov->local()->extraDataSizes.devPtr())
	}

	helper->bufSizes.popStream();
}

void ObjectRedistributor::combineAndUploadData(int id)
{
	auto ov = objects[id];
	auto helper = helpers[id];

	ov->halo()->resize(helper->recvOffsets[27] * ov->halo()->objSize, resizeAnew);
	ov->halo()->resize(helper->recvOffsets[27] * ov->halo()->objSize, resizeAnew);

	const int nthreads = 128;
	for (int i=0; i < 27; i++)
	{
		const int nObjs = helper->recvOffsets[i+1] - helper->recvOffsets[i];
		if (nObjs > 0)
		{
			int        nPtrs = ov->local()->extraDataPtrs.size();
			int totSize_byte = ov->local()->packedObjSize_bytes;

			unpackObject<<< nObjs, nthreads, 0, defStream >>>
					((float4*)helper->recvBufs[i].devPtr(), (float4*)(ov->halo()->coosvels.devPtr() + helper->recvOffsets[i]*nObjs), ov->local()->objSize, totSize_byte, nObjs,
					 ov->halo()->extraDataPtrs.devPtr(), nPtrs, ov->halo()->extraDataSizes.devPtr());
		}
	}
}



