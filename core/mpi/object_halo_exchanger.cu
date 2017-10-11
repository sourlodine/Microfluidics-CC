#include "object_halo_exchanger.h"

#include <core/pvs/particle_vector.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/rigid_object_vector.h>
#include <core/logger.h>
#include <core/utils/cuda_common.h>

template<bool QUERY=false>
__global__ void getObjectHalos(const OVviewWithExtraData ovView, const ROVview rovView,
		const float rc, char** dests, int* sendBufSizes, int** haloParticleIds = nullptr)
{
	const int objId = blockIdx.x;
	const int tid = threadIdx.x;
	const int sh  = tid % 2;

	int nHalos = 0;
	short validHalos[7];

	if (objId < ovView.nObjects)
	{
		// Find to which halos this object should go
		auto prop = ovView.comAndExtents[objId];
		int cx = 1, cy = 1, cz = 1;

		if (prop.low.x  < -0.5f*ovView.localDomainSize.x + rc) cx = 0;
		if (prop.low.y  < -0.5f*ovView.localDomainSize.y + rc) cy = 0;
		if (prop.low.z  < -0.5f*ovView.localDomainSize.z + rc) cz = 0;

		if (prop.high.x >  0.5f*ovView.localDomainSize.x - rc) cx = 2;
		if (prop.high.y >  0.5f*ovView.localDomainSize.y - rc) cy = 2;
		if (prop.high.z >  0.5f*ovView.localDomainSize.z - rc) cz = 2;

//			if (tid == 0 && !QUERY) printf("Obj %d : [%f %f %f] -- [%f %f %f]\n", objId,
//			prop.low.x, prop.low.y, prop.low.z, prop.high.x, prop.high.y, prop.high.z);

		for (int ix = min(cx, 1); ix <= max(cx, 1); ix++)
			for (int iy = min(cy, 1); iy <= max(cy, 1); iy++)
				for (int iz = min(cz, 1); iz <= max(cz, 1); iz++)
				{
					if (ix == 1 && iy == 1 && iz == 1) continue;
					const int bufId = (iz*3 + iy)*3 + ix;
					validHalos[nHalos] = bufId;
					nHalos++;
				}
	}

	// Copy objects to each halo
	// TODO: maybe other loop order?
	__shared__ int shDstObjId;
	for (int i=0; i<nHalos; i++)
	{
		const int bufId = validHalos[i];

		const int ix = bufId % 3;
		const int iy = (bufId / 3) % 3;
		const int iz = bufId / 9;
		const float3 shift{ ovView.localDomainSize.x*(ix-1),
							ovView.localDomainSize.y*(iy-1),
							ovView.localDomainSize.z*(iz-1) };

		__syncthreads();
		if (tid == 0)
			shDstObjId = atomicAdd(sendBufSizes + bufId, 1);

		if (QUERY)
			continue;

		__syncthreads();

//		if (tid == 0)
//			printf("obj  %d  to halo  %d\n", objId, bufId);

		float4* dstAddr = (float4*) (dests[bufId]) + ovView.packedObjSize_byte/sizeof(float4) * shDstObjId;

		for (int pid = tid/2; pid < ovView.objSize; pid += blockDim.x/2)
		{
			const int srcId = objId * ovView.objSize + pid;
			Float3_int data(ovView.particles[2*srcId + sh]);

			// Remember your origin, little particle!
			if (sh == 1)
			{
				haloParticleIds[bufId][shDstObjId * ovView.objSize + pid] = srcId;

				data.s2 = objId;
				data.s1 = pid;
			}

			if (sh == 0)
				data.v -= shift;

			dstAddr[2*pid + sh] = data.toFloat4();
		}

		// Add extra data at the end of the object
		dstAddr += ovView.objSize*2;
		ovView.packExtraData(objId, (char*)dstAddr);

		if (rovView.objSize == ovView.objSize)
			rovView.applyShift2extraData((char*)dstAddr, shift);
	}
}

__global__ static void unpackObject(const float4* from, const int startDstObjId, OVviewWithExtraData ovView)
{
	const int objId = blockIdx.x;
	const int tid = threadIdx.x;
	const int sh  = tid % 2;

	const float4* srcAddr = from + ovView.packedObjSize_byte/sizeof(float4) * objId;

	for (int pid = tid/2; pid < ovView.objSize; pid += blockDim.x/2)
	{
		const int dstId = (startDstObjId+objId)*ovView.objSize + pid;
		ovView.particles[2*dstId + sh] = srcAddr[2*pid + sh];
	}

	ovView.unpackExtraData( startDstObjId+objId, (char*)(srcAddr + 2*ovView.objSize));
}


void ObjectHaloExchanger::attach(ObjectVector* ov, float rc)
{
	objects.push_back(ov);
	rcs.push_back(rc);
	ExchangeHelper* helper = new ExchangeHelper(ov->name);
	helpers.push_back(helper);

	ExchangeHelper* originHelper = new ExchangeHelper(ov->name, sizeof(int)*ov->objSize);
	originHelpers.push_back(originHelper);

	info("Object vector %s (rc %f) was attached to halo exchanger", ov->name.c_str(), rc);
}


void ObjectHaloExchanger::prepareData(int id, cudaStream_t stream)
{
	auto ov  = objects[id];
	auto rc  = rcs[id];
	auto helper = helpers[id];
	auto originHelper = originHelpers[id];

	debug2("Preparing %s halo on the device", ov->name.c_str());

	auto ovView = create_OVviewWithExtraData(ov, ov->local(), stream);
	helper->setDatumSize(ovView.packedObjSize_byte);
	helper->sendBufSizes.clear(stream);

	const int nthreads = 128;
	if (ovView.nObjects > 0)
	{
		// FIXME: this is a hack
		auto rovView = create_ROVview(nullptr, nullptr);
		RigidObjectVector* rov;
		if ( (rov = dynamic_cast<RigidObjectVector*>(ov)) != 0 )
			rovView = create_ROVview(rov, rov->local());

		getObjectHalos<true>  <<< ovView.nObjects, nthreads, 0, stream >>> (
				ovView, rovView, rc, helper->sendAddrs.devPtr(), helper->sendBufSizes.devPtr());

		helper->sendBufSizes.downloadFromDevice(stream);
		for (int i=0; i<helper->sendBufSizes.size(); i++)
			originHelper->sendBufSizes[i] = helper->sendBufSizes[i];

		helper->resizeSendBufs();
		originHelper->resizeSendBufs();

		helper->sendBufSizes.clearDevice(stream);
		getObjectHalos<false> <<< ovView.nObjects, nthreads, 0, stream >>> (
				ovView, rovView, rc, helper->sendAddrs.devPtr(), helper->sendBufSizes.devPtr(), (int**)originHelper->sendAddrs.devPtr());
	}
}

void ObjectHaloExchanger::combineAndUploadData(int id, cudaStream_t stream)
{
	auto ov = objects[id];
	auto helper = helpers[id];

	ov->halo()->resize_anew(helper->recvOffsets[27] * ov->objSize);
	auto ovView = create_OVviewWithExtraData(ov, ov->halo(), stream);

	// TODO: unite into one unpack call
	const int nthreads = 128;
	for (int i=0; i < 27; i++)
	{
		const int nObjs = helper->recvOffsets[i+1] - helper->recvOffsets[i];
		if (nObjs > 0)
		{
			helper->recvBufs[i].uploadToDevice(stream);
			unpackObject<<< nObjs, nthreads, 0, stream >>> ( (float4*)helper->recvBufs[i].devPtr(),  helper->recvOffsets[i], ovView );
		}
	}
}

std::vector<int>& ObjectHaloExchanger::getRecvOffsets(int id)
{
	return helpers[id]->recvOffsets;
}

PinnedBuffer<char*>& ObjectHaloExchanger::getOriginAddrs(int id)
{
	return originHelpers[id]->sendAddrs;
}




