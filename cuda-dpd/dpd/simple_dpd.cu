#include <cstdio>
#include <helper_math.h>
#include <cuda_fp16.h>
#include <cassert>
#include "../tiny-float.h"

#include "cuda-dpd.h"
#include "../dpd-rng.h"

__device__ __forceinline__ float3 readCoosFromAll4(const float4* xyzouvwo, int pid)
{
	const float4 tmp = xyzouvwo[2*pid];

	return make_float3(tmp.x, tmp.y, tmp.z);
}

__device__ __forceinline__ void readAll4(const float4* xyzouvwo, int pid, float3& coo, float3& vel)
{
	const float4 tmp1 = xyzouvwo[pid*2];
	const float4 tmp2 = xyzouvwo[pid*2+1];

	coo = make_float3(tmp1.x, tmp1.y, tmp1.z);
	vel = make_float3(tmp2.x, tmp2.y, tmp2.z);
}

__device__ __forceinline__ int getCellId(const float x, const float start, const float invrc, const int ncells)
{
	const float v = invrc * (x - start);
	const float robustV = min(min(floor(v), floor(v - 1.0e-6f)), floor(v + 1.0e-6f));
	return min(ncells - 1, max(0, (int)robustV));
}

__device__ __forceinline__ float sqr(float x)
{
	return x*x;
}

template<typename Ta, typename Tb>
__device__ __forceinline__ float distance2(const Ta a, const Tb b)
{
	return sqr(a.x - b.x) + sqr(a.y - b.y) + sqr(a.z - b.z);
}

//__launch_bounds__(128, 16)
template<typename Interaction>
__global__ void computeSelfInteractions(const float4 * __restrict__ xyzouvwo, float* axayaz, const int * __restrict__ cellsstart,
		int3 ncells, float3 domainStart, int ncells_1, int np, Interaction interaction)
{
	const int dstId = blockIdx.x*blockDim.x + threadIdx.x;
	if (dstId >= np) return;

	float3 dstCoo, dstVel;
	float3 dstAcc = make_float3(0.0f);
	readAll4(xyzouvwo, dstId, dstCoo, dstVel);

	const int cellX0 = getCellId(dstCoo.x, domainStart.x, 1.0f, ncells.x);
	const int cellY0 = getCellId(dstCoo.y, domainStart.y, 1.0f, ncells.y);
	const int cellZ0 = getCellId(dstCoo.z, domainStart.z, 1.0f, ncells.z);

#pragma unroll
	for (int cellY = cellY0-1; cellY <= cellY0; cellY++)
		for (int cellZ = cellZ0-1; cellZ <= cellZ0+1; cellZ++)
		{
			if ( !(cellY >= 0 && cellY < ncells.y && cellZ >= 0 && cellZ < ncells.z) ) continue;
			if (cellY == cellY0 && cellZ > cellZ0) continue;

			const int midCellId = (cellZ*ncells.y + cellY)*ncells.x + cellX0;
			int rowStart  = max(midCellId-1, 0);
			int rowEnd    = min(midCellId+2, ncells_1);
			if ( cellY == cellY0 && cellZ == cellZ0 ) rowEnd = midCellId + 1; // this row is already partly covered

			const int pstart = cellsstart[rowStart];
			const int pend   = cellsstart[rowEnd];

			for (int srcId = pstart; srcId < pend; srcId ++)
			{
				const float3 srcCoo = readCoosFromAll4(xyzouvwo, srcId);

				bool interacting = distance2(srcCoo, dstCoo) < 1.00f;
				if (dstId <= srcId && cellY == cellY0 && cellZ == cellZ0) interacting = false;

				if (interacting)
				{
					float3 srcCoo, srcVel;
					readAll4(xyzouvwo, srcId, srcCoo, srcVel);

					float3 frc = interaction(dstCoo, dstVel, dstId, srcCoo, srcVel, srcId);

					dstAcc += frc;

					float* dest = axayaz + srcId*3;
					atomicAdd(dest,     -frc.x);
					atomicAdd(dest + 1, -frc.y);
					atomicAdd(dest + 2, -frc.z);
				}
			}
		}

	float* dest = axayaz + dstId*3;
	atomicAdd(dest,     dstAcc.x);
	atomicAdd(dest + 1, dstAcc.y);
	atomicAdd(dest + 2, dstAcc.z);
}


__device__ __forceinline__ float3 dpd_interaction(
		const float3 dstCoo, const float3 dstVel, const int dstId,
		const float3 srcCoo, const float3 srcVel, const int srcId,
		float adpd, float gammadpd, float sigmadpd, float seed)
{
	const float _xr = dstCoo.x - srcCoo.x;
	const float _yr = dstCoo.y - srcCoo.y;
	const float _zr = dstCoo.z - srcCoo.z;
	const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;
	if (rij2 > 1.0f) return make_float3(0.0f);

	const float invrij = rsqrtf(rij2);
	const float rij = rij2 * invrij;
	const float argwr = 1.0f - rij;
	const float wr = viscosity_function<0>(argwr);

	const float xr = _xr * invrij;
	const float yr = _yr * invrij;
	const float zr = _zr * invrij;

	const float rdotv =
			xr * (dstVel.x - srcVel.x) +
			yr * (dstVel.y - srcVel.y) +
			zr * (dstVel.z - srcVel.z);

	const float myrandnr = 0*Logistic::mean0var1(seed, min(srcId, dstId), max(srcId, dstId));

	const float strength = adpd * argwr - (gammadpd * wr * rdotv + sigmadpd * myrandnr) * wr;

	return make_float3(strength * xr, strength * yr, strength * zr);
}


template<typename T>
struct SimpleDeviceBuffer
{
	int capacity, size;

	T * data;

	SimpleDeviceBuffer(int n = 0): capacity(0), size(0), data(NULL) { resize(n);}

	~SimpleDeviceBuffer()
	{
		if (data != NULL)
			cudaFree(data);

		data = NULL;
	}

	void dispose()
	{
		if (data != NULL)
			cudaFree(data);

		data = NULL;
	}

	void resize(const int n)
	{
		assert(n >= 0);

		size = n;

		if (capacity >= n)
			return;

		if (data != NULL)
			cudaFree(data);

		const int conservative_estimate = (int)ceil(1.1 * n);
		capacity = 128 * ((conservative_estimate + 129) / 128);

		cudaMalloc(&data, sizeof(T) * capacity);

#ifndef NDEBUG
		cudaMemset(data, 0, sizeof(T) * capacity);
#endif
	}
};



void forces_dpd_cuda_nohost( const float * const xyzuvw, const float4 * const xyzouvwo, const ushort4 * const xyzo_half, float * const axayaz,  const int np,
		const int * const cellsstart, const int * const cellscount,
		const float rc,
		const float XL, const float YL, const float ZL,
		const float adpd,
		const float gammadpd,
		const float sigmadpd,
		const float invsqrtdt,
		const float seed, cudaStream_t stream )
{
	const int nx = round(XL / rc);
	const int ny = round(YL / rc);
	const int nz = round(ZL / rc);

	auto dpdInt = [=] __device__ ( const float3 dstCoo, const float3 dstVel, const int dstId,
					   const float3 srcCoo, const float3 srcVel, const int srcId) {
		return dpd_interaction(dstCoo, dstVel, dstId, srcCoo, srcVel, srcId,
			adpd, gammadpd, sigmadpd*invsqrtdt, seed);
	};

	cudaFuncSetCacheConfig( computeSelfInteractions<decltype(dpdInt)>, cudaFuncCachePreferL1 );

	cudaMemsetAsync( axayaz, 0, sizeof( float )* np * 3, stream );
	const int nth = 128;
	computeSelfInteractions<<< (np + nth - 1) / nth, nth, 0, stream >>>(xyzouvwo, axayaz, cellsstart,
			make_int3(nx, ny, nz), make_float3(-nx/2, -ny/2, -nz/2), nx*ny*nz+1, np, dpdInt);
}




