#include "particle_halo_exchanger.h"

#include <core/pvs/particle_vector.h>
#include <core/celllist.h>
#include <core/logger.h>
#include <core/cuda_common.h>

#include "valid_cell.h"

template<bool QUERY=false>
__global__ void getHalos(const float4* __restrict__ coosvels, const CellListInfo cinfo, const uint* __restrict__ cellsStartSize,
		const int64_t dests[27], int counts[27])
{
	const int gid = blockIdx.x*blockDim.x + threadIdx.x;
	const int tid = threadIdx.x;
	int cid;
	int cx, cy, cz;

	bool valid = isValidCell(cid, cx, cy, cz, gid, blockIdx.y, cinfo);

	if (__all(!valid) && tid > 27) return;

	int2 start_size = valid ? cinfo.decodeStartSize(cellsStartSize[cid]) : make_int2(0, 0);

	// Use shared memory to decrease number of global atomics
	// We're sending to max 7 halos (corner)
	short validHalos[7];
	int haloOffset[7] = {};

	int current = 0;

	// Total number of elements written to halos by this block
	__shared__ int blockSum[27];
	if (tid < 27) blockSum[tid] = 0;

	__syncthreads();

	for (int ix = min(cx, 1); ix <= max(cx, 1); ix++)
		for (int iy = min(cy, 1); iy <= max(cy, 1); iy++)
			for (int iz = min(cz, 1); iz <= max(cz, 1); iz++)
			{
				if (ix == 1 && iy == 1 && iz == 1) continue;

				const int bufId = (iz*3 + iy)*3 + ix;
				validHalos[current] = bufId;
				haloOffset[current] = atomicAdd(blockSum + bufId, start_size.y);
				current++;
			}

	__syncthreads();

	if (tid < 27 && blockSum[tid] > 0)
		blockSum[tid] = atomicAdd(counts + tid, blockSum[tid]);

	if (QUERY) return;

	__syncthreads();

#pragma unroll 3
	for (int i=0; i<current; i++)
	{
		const int bufId = validHalos[i];
		const int myid  = blockSum[bufId] + haloOffset[i];

		const int ix = bufId % 3;
		const int iy = (bufId / 3) % 3;
		const int iz = bufId / 9;
		const float3 shift{ cinfo.localDomainSize.x*(ix-1),
							cinfo.localDomainSize.y*(iy-1),
							cinfo.localDomainSize.z*(iz-1) };

#pragma unroll 2
		for (int i = 0; i < start_size.y; i++)
		{
			const int dstInd = myid         + i;
			const int srcInd = start_size.x + i;

			Particle p(coosvels, srcInd);
			p.r -= shift;

			float4* addr = (float4*)dests[bufId];
			addr[2*dstInd + 0] = p.r2Float4();
			addr[2*dstInd + 1] = p.u2Float4();
		}
	}
}

void ParticleHaloExchanger::attach(ParticleVector* pv, CellList* cl)
{
	particles.push_back(pv);
	cellLists.push_back(cl);

	auto helper = new ExchangeHelper(pv->name, sizeof(Particle));
	helpers.push_back(helper);

	info("Particle halo exchanger takes pv %s, base tag %d", pv->name.c_str(), tagByName(pv->name));
}

void ParticleHaloExchanger::combineAndUploadData(int id, cudaStream_t stream)
{
	auto pv = particles[id];
	auto helper = helpers[id];

	pv->halo()->resize(helper->recvOffsets[27], stream, ResizeKind::resizeAnew);

	for (int i=0; i < 27; i++)
	{
		const int msize = helper->recvOffsets[i+1] - helper->recvOffsets[i];
		if (msize > 0)
			CUDA_Check( cudaMemcpyAsync(pv->halo()->coosvels.devPtr() + helper->recvOffsets[i], helper->recvBufs[i].hostPtr(),
					msize*sizeof(Particle), cudaMemcpyHostToDevice, stream) );
	}
}

void ParticleHaloExchanger::prepareData(int id, cudaStream_t stream)
{
	auto pv = particles[id];
	auto cl = cellLists[id];
	auto helper = helpers[id];

	debug2("Preparing %s halo on the device", pv->name.c_str());


	const int maxdim = std::max({cl->ncells.x, cl->ncells.y, cl->ncells.z});
	const int nthreads = 32;
	if (pv->local()->size() > 0)
	{
		helper->sendBufSizes.clearDevice(stream);
		getHalos<true>  <<< dim3((maxdim*maxdim + nthreads - 1) / nthreads, 6, 1),  dim3(nthreads, 1, 1), 0, stream >>> (
				(float4*)pv->local()->coosvels.devPtr(), cl->cellInfo(), cl->cellsStartSize.devPtr(),
				(int64_t*)helper->sendAddrs.devPtr(), helper->sendBufSizes.devPtr() );

		helper->sendBufSizes.downloadFromDevice(stream);
		helper->resizeSendBufs(stream);

		helper->sendBufSizes.clearDevice(stream);
		getHalos<false> <<< dim3((maxdim*maxdim + nthreads - 1) / nthreads, 6, 1),  dim3(nthreads, 1, 1), 0, stream >>> (
				(float4*)pv->local()->coosvels.devPtr(), cl->cellInfo(), cl->cellsStartSize.devPtr(),
				(int64_t*)helper->sendAddrs.devPtr(), helper->sendBufSizes.devPtr() );
	}

	debug2("%s halo prepared", pv->name.c_str());
}




