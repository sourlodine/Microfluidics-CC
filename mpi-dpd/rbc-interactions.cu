/*
 *  rbc-interactions.cu
 *  Part of CTC/mpi-dpd/
 *
 *  Created and authored by Diego Rossinelli on 2014-12-02.
 *  Copyright 2015. All rights reserved.
 *
 *  Users are NOT authorized
 *  to employ the present software for their own publications
 *  before getting a written permission from the author of this file.
 */

#include <set>
#include <../dpd-rng.h>

#include "rbc-interactions.h"
#include "minmax-massimo.h"

namespace KernelsRBC
{
    struct ParamsFSI
    {
	float aij, gamma, sigmaf;
    };

    __constant__ ParamsFSI params;

    texture<float2, cudaTextureType1D> texSolventParticles;
    texture<int, cudaTextureType1D> texCellsStart, texCellsCount;

    static bool firsttime = true;

    __global__ void fsi_forces(const float seed,
			       Acceleration * accsolvent, const int npsolvent,
			       const Particle * const particle, const int nparticles, Acceleration * accrbc);

    void setup(const Particle * const solvent, const int npsolvent, const int * const cellsstart, const int * const cellscount)
    {
	if (firsttime)
	{
	    texCellsStart.channelDesc = cudaCreateChannelDesc<int>();
	    texCellsStart.filterMode = cudaFilterModePoint;
	    texCellsStart.mipmapFilterMode = cudaFilterModePoint;
	    texCellsStart.normalized = 0;

	    texCellsCount.channelDesc = cudaCreateChannelDesc<int>();
	    texCellsCount.filterMode = cudaFilterModePoint;
	    texCellsCount.mipmapFilterMode = cudaFilterModePoint;
	    texCellsCount.normalized = 0;

	    texSolventParticles.channelDesc = cudaCreateChannelDesc<float2>();
	    texSolventParticles.filterMode = cudaFilterModePoint;
	    texSolventParticles.mipmapFilterMode = cudaFilterModePoint;
	    texSolventParticles.normalized = 0;
	    firsttime = false;
	}

	size_t textureoffset;
	CUDA_CHECK(cudaBindTexture(&textureoffset, &texSolventParticles, solvent, &texSolventParticles.channelDesc,
				   sizeof(float) * 6 * npsolvent));

	const int ncells = XSIZE_SUBDOMAIN * YSIZE_SUBDOMAIN * ZSIZE_SUBDOMAIN;

	assert(textureoffset == 0);
	CUDA_CHECK(cudaBindTexture(&textureoffset, &texCellsStart, cellsstart, &texCellsStart.channelDesc, sizeof(int) * ncells));
	assert(textureoffset == 0);
	CUDA_CHECK(cudaBindTexture(&textureoffset, &texCellsCount, cellscount, &texCellsCount.channelDesc, sizeof(int) * ncells));
	assert(textureoffset == 0);

	CUDA_CHECK(cudaFuncSetCacheConfig(fsi_forces, cudaFuncCachePreferL1));
    }

    __global__ void shift_send_particles_kernel(const Particle * const src, const int n, const int code, Particle * const dst)
    {
	const int gid = threadIdx.x + blockDim.x * blockIdx.x;

	const int d[3] = { (code + 2) % 3 - 1, (code / 3 + 2) % 3 - 1, (code / 9 + 2) % 3 - 1 };
	const int L[3] = { XSIZE_SUBDOMAIN, YSIZE_SUBDOMAIN, ZSIZE_SUBDOMAIN };

	if (gid < n)
	{
	    Particle p = src[gid];

	    for(int c = 0; c < 3; ++c)
		p.x[c] -= d[c] * L[c];

	    dst[gid] = p;
	}
    }

    static const int cmaxnrbcs = 64;
    __constant__ float * csources[cmaxnrbcs], * cdestinations[cmaxnrbcs];
    __constant__ int ccodes[cmaxnrbcs];

    template <bool from_cmem>
    __global__ void shift_all_send_particles(const int nrbcs, const int nvertices,
					     const float ** const dsources, const int * dcodes, float ** const ddestinations)
    {
	const int nfloats_per_rbc = 6 * nvertices;

	assert(nfloats_per_rbc * nrbcs <= blockDim.x * gridDim.x);

	const int gid = threadIdx.x + blockDim.x * blockIdx.x;

	if (gid >= nfloats_per_rbc * nrbcs)
	    return;

	const int idrbc = gid / nfloats_per_rbc;
	assert(idrbc < nrbcs);

	const int offset = gid % nfloats_per_rbc;

	float val;
	if (from_cmem)
	    val = csources[idrbc][offset];
	else
	    val = dsources[idrbc][offset];

	int code;
	if (from_cmem)
	    code = ccodes[idrbc];
	else
	    code = dcodes[idrbc];

	const int c = gid % 6;

	val -=
	    (c == 0) * ((code     + 2) % 3 - 1) * XSIZE_SUBDOMAIN +
	    (c == 1) * ((code / 3 + 2) % 3 - 1) * YSIZE_SUBDOMAIN +
	    (c == 2) * ((code / 9 + 2) % 3 - 1) * ZSIZE_SUBDOMAIN ;

	if (from_cmem)
	    cdestinations[idrbc][offset] = val;
	else
	    ddestinations[idrbc][offset] = val;
    }

    SimpleDeviceBuffer<float *> _ddestinations;
    SimpleDeviceBuffer<const float *> _dsources;
    SimpleDeviceBuffer<int> _dcodes;

    void dispose()
    {
	_ddestinations.dispose();
	_dsources.dispose();
	_dcodes.dispose();
    }

    void shift_send_particles(cudaStream_t stream, const int nrbcs, const int nvertices,
			      const float ** const sources, const int * codes, float ** const destinations)
    {
	if (nrbcs == 0)
	    return;

	const int nthreads = nrbcs * nvertices * 6;

	if (nrbcs < cmaxnrbcs)
	{
	    CUDA_CHECK(cudaMemcpyToSymbolAsync(ccodes, codes, sizeof(int) * nrbcs, 0, cudaMemcpyHostToDevice, stream));
	    CUDA_CHECK(cudaMemcpyToSymbolAsync(cdestinations, destinations, sizeof(float *) * nrbcs, 0, cudaMemcpyHostToDevice, stream));
	    CUDA_CHECK(cudaMemcpyToSymbolAsync(csources, sources, sizeof(float *) * nrbcs, 0, cudaMemcpyHostToDevice, stream));

	    shift_all_send_particles<true><<<(nthreads + 127) / 128, 128, 0, stream>>>
		(nrbcs, nvertices, NULL, NULL, NULL);

	    CUDA_CHECK(cudaPeekAtLastError());
	}
	else
	{
	    _dcodes.resize(nrbcs);
	    _ddestinations.resize(nrbcs);
	    _dsources.resize(nrbcs);

	    CUDA_CHECK(cudaMemcpyAsync(_dcodes.data, codes, sizeof(int) * nrbcs, cudaMemcpyHostToDevice, stream));
	    CUDA_CHECK(cudaMemcpyAsync(_ddestinations.data, destinations, sizeof(float *) * nrbcs, cudaMemcpyHostToDevice, stream));
	    CUDA_CHECK(cudaMemcpyAsync(_dsources.data, sources, sizeof(float *) * nrbcs, cudaMemcpyHostToDevice, stream));

	    shift_all_send_particles<false><<<(nthreads + 127) / 128, 128, 0, stream>>>
		(nrbcs, nvertices, _dsources.data, _dcodes.data, _ddestinations.data);
	}
    }

    template <bool from_cmem>
    __global__ void merge_all_acc(const int nrbcs, const int nvertices,
				  const float ** const dsources, float ** const ddestinations)
    {
	if (nrbcs == 0)
	    return;

	const int nfloats_per_rbc = 3 * nvertices;

	assert(nfloats_per_rbc * nrbcs <= blockDim.x * gridDim.x);

	const int gid = threadIdx.x + blockDim.x * blockIdx.x;

	if (gid >= nfloats_per_rbc * nrbcs)
	    return;

	const int idrbc = gid / nfloats_per_rbc;
	assert(idrbc < nrbcs);

	const int offset = gid % nfloats_per_rbc;

	float val;
	if (from_cmem)
	    val = csources[idrbc][offset];
	else
	    val = dsources[idrbc][offset];

	if (from_cmem)
	    atomicAdd(cdestinations[idrbc] + offset, val);
	else
	    atomicAdd(ddestinations[idrbc] + offset, val);
    }

    void merge_all_accel(cudaStream_t stream, const int nrbcs, const int nvertices,
			 const float ** const sources, float ** const destinations)
    {
	if (nrbcs == 0)
	    return;

	const int nthreads = nrbcs * nvertices * 3;

	CUDA_CHECK(cudaPeekAtLastError());

	if (nrbcs < cmaxnrbcs)
	{
	    CUDA_CHECK(cudaMemcpyToSymbolAsync(cdestinations, destinations, sizeof(float *) * nrbcs, 0, cudaMemcpyHostToDevice, stream));
	    CUDA_CHECK(cudaMemcpyToSymbolAsync(csources, sources, sizeof(float *) * nrbcs, 0, cudaMemcpyHostToDevice, stream));

	    merge_all_acc<true><<<(nthreads + 127) / 128, 128, 0, stream>>>(nrbcs, nvertices, NULL, NULL);

	    CUDA_CHECK(cudaPeekAtLastError());
	}
	else
	{
	    _ddestinations.resize(nrbcs);
	    _dsources.resize(nrbcs);

	    CUDA_CHECK(cudaMemcpyAsync(_ddestinations.data, destinations, sizeof(float *) * nrbcs, cudaMemcpyHostToDevice, stream));
	    CUDA_CHECK(cudaMemcpyAsync(_dsources.data, sources, sizeof(float *) * nrbcs, cudaMemcpyHostToDevice, stream));

	    merge_all_acc<false><<<(nthreads + 127) / 128, 128, 0, stream>>>(nrbcs, nvertices, _dsources.data, _ddestinations.data);
	}
    }

    __device__ bool fsi_kernel(const float seed,
			       const int dpid, const float3 xp, const float3 up, const int spid,
			       float& xforce, float& yforce, float& zforce)
    {
	xforce = yforce = zforce = 0;

	const int sentry = 3 * spid;

	const float2 stmp0 = tex1Dfetch(texSolventParticles, sentry);
	const float2 stmp1 = tex1Dfetch(texSolventParticles, sentry + 1);
	const float2 stmp2 = tex1Dfetch(texSolventParticles, sentry + 2);

	const float _xr = xp.x - stmp0.x;
	const float _yr = xp.y - stmp0.y;
	const float _zr = xp.z - stmp1.x;

	const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;

	if (rij2 > 1)
	    return false;

	const float invrij = rsqrtf(rij2);

	const float rij = rij2 * invrij;
	const float argwr = max((float)0, 1 - rij);
	const float wr = powf(argwr, powf(0.5f, -VISCOSITY_S_LEVEL));

	const float xr = _xr * invrij;
	const float yr = _yr * invrij;
	const float zr = _zr * invrij;

	const float rdotv =
	    xr * (up.x - stmp1.y) +
	    yr * (up.y - stmp2.x) +
	    zr * (up.z - stmp2.y);

	//const float mysaru = saru(saru_tag, dpid, spid);
	//const float myrandnr = 3.464101615f * mysaru - 1.732050807f;
	const float myrandnr = Logistic::mean0var1(seed, dpid, spid);

	const float strength = params.aij * argwr +  (- params.gamma * wr * rdotv + params.sigmaf * myrandnr) * wr;

	xforce = strength * xr;
	yforce = strength * yr;
	zforce = strength * zr;

	return true;
    }

    __device__ float3 fsi_interaction(const float seed,
				      const int dpid, const float3 up, const int spid,
				      const float2 stmp1, const float2 stmp2,
				      const float _xr, const float _yr, const float _zr, const float rij2)
    {
	const float invrij = rsqrtf(rij2);

	const float rij = rij2 * invrij;
	const float argwr = 1 - rij;
	const float wr = viscosity_function<-VISCOSITY_S_LEVEL>(argwr);

	const float xr = _xr * invrij;
	const float yr = _yr * invrij;
	const float zr = _zr * invrij;

	const float rdotv =
	    xr * (up.x - stmp1.y) +
	    yr * (up.y - stmp2.x) +
	    zr * (up.z - stmp2.y);

	const float myrandnr = Logistic::mean0var1(seed, dpid, spid);

	const float strength = params.aij * argwr +  (- params.gamma * wr * rdotv + params.sigmaf * myrandnr) * wr;

	return make_float3(strength * xr, strength * yr, strength * zr);
    }


    template<int XCPB, int YCPB, int ZCPB, int COLS, int ROWS>
    __global__ void fsi_forces(const float seed,
			       cudaTextureObject_t texSoluteCellStart,
			       cudaTextureObject_t texSoluteParticles,
			       float * const accsolute, const int nsolute,
			       float * const accsolvent, const int nsolvent)
    {
	enum { CPB = XCPB * YCPB * ZCPB };

	assert(warpSize == COLS * ROWS);
	assert(blockDim.x == warpSize && blockDim.y == CPB && blockDim.z == 1);
	assert(ROWS * 3 <= warpSize);

	const int tid = threadIdx.x;
	const int wid = threadIdx.y;

	const int subtid = tid % COLS;
	const int slot = tid / COLS;

	__shared__ int volatile starts[CPB][32], scan[CPB][32];

	const int xmycid = blockIdx.x * XCPB + ((wid) % XCPB);
	const int ymycid = blockIdx.y * YCPB + ((wid / XCPB) % YCPB);
	const int zmycid = blockIdx.z * ZCPB + ((wid / (XCPB * YCPB)) % ZCPB);
	const int mycid = xmycid + XSIZE_SUBDOMAIN * (ymycid + YSIZE_SUBDOMAIN * zmycid);

	int mycount = 0, myscan = 0;

	if (tid < 27)
	{
	    const int dx = tid % 3;
	    const int dy = (tid / 3) % 3;
	    const int dz = (tid / 9) % 3;

	    int xcid = xmycid + dx - 1;
	    int ycid = ymycid + dy - 1;
	    int zcid = zmycid + dz - 1;

	    const bool valid_cid =
		xcid >= 0 && xcid < XSIZE_SUBDOMAIN &&
		ycid >= 0 && ycid < YSIZE_SUBDOMAIN &&
		zcid >= 0 && zcid < ZSIZE_SUBDOMAIN ;

	    xcid = min(XSIZE_SUBDOMAIN - 1, max(0, xcid));
	    ycid = min(YSIZE_SUBDOMAIN - 1, max(0, ycid));
	    zcid = min(ZSIZE_SUBDOMAIN - 1, max(0, zcid));

	    const int cid = max(0, xcid + XSIZE_SUBDOMAIN * (ycid + YSIZE_SUBDOMAIN * zcid));

	    starts[wid][tid] = tex1Dfetch(texCellsStart, cid);

	    myscan = mycount = valid_cid * tex1Dfetch(texCellsCount, cid);
	}

	for(int L = 1; L < 32; L <<= 1)
	    myscan += (tid >= L) * __shfl_up(myscan, L);

	if (tid < 28)
	    scan[wid][tid] = myscan - mycount;

	const int nsrc = scan[wid][27];

	const int dststart = tex1Dfetch<int>(texSoluteCellStart, mycid);
	const int lastdst = tex1Dfetch<int>(texSoluteCellStart, mycid + 1);

	for(int pid = subtid; pid < nsrc; pid += COLS)
	{
	    const int key9 = 9 * ((pid >= scan[wid][9]) + (pid >= scan[wid][18]));
	    const int key3 = 3 * ((pid >= scan[wid][key9 + 3]) + (pid >= scan[wid][key9 + 6]));
	    const int key = key9 + key3;

	    const int spid = pid - scan[wid][key] + starts[wid][key];
	    const int sentry = 3 * spid;
	    const float2 stmp0 = tex1Dfetch(texSolventParticles, sentry);
	    const float2 stmp1 = tex1Dfetch(texSolventParticles, sentry + 1);

	    for(int dpid = dststart + slot; dpid < lastdst; dpid += ROWS)
	    {
		float3 xdest, udest;

		float2 dtmp0 = tex1Dfetch<float2>(texSoluteParticles, 3 * dpid);
		xdest.x = dtmp0.x;
		xdest.y = dtmp0.y;

		dtmp0 = tex1Dfetch<float2>(texSoluteParticles, 3 * dpid + 1);
		xdest.z = dtmp0.x;
		udest.x = dtmp0.y;

		dtmp0 = tex1Dfetch<float2>(texSoluteParticles, 3 * dpid + 2);
		udest.y = dtmp0.x;
		udest.z = dtmp0.y;

		const float xr = xdest.x - stmp0.x;
		const float yr = xdest.y - stmp0.y;
		const float zr = xdest.z - stmp1.x;
		const float rij2 = xr * xr + yr * yr + zr * zr;

		if (rij2 < 1.0f)
		{
		    const float2 stmp2 = tex1Dfetch(texSolventParticles, sentry + 2);
		    const float3 f = fsi_interaction(seed, dpid, udest, spid, stmp1, stmp2, xr, yr, zr, rij2);

		    atomicAdd(accsolute + 3 * dpid    , f.x);
		    atomicAdd(accsolute + 3 * dpid + 1, f.y);
		    atomicAdd(accsolute + 3 * dpid + 2, f.z);

		    atomicAdd(accsolvent + 3 * spid    , -f.x);
		    atomicAdd(accsolvent + 3 * spid + 1, -f.y);
		    atomicAdd(accsolvent + 3 * spid + 2, -f.z);
		}
	    }
	}
    }

    __global__ void fsi_forces(const float seed,
			       Acceleration * accsolvent, const int npsolvent,
			       const Particle * const particle, const int nparticles, Acceleration * accrbc)
    {
	const int dpid = threadIdx.x + blockDim.x * blockIdx.x;

	if (dpid >= nparticles)
	    return;

	const Particle p = particle[dpid];

	const float3 xp = make_float3(p.x[0], p.x[1], p.x[2]);
	const float3 up = make_float3(p.u[0], p.u[1], p.u[2]);

	const int L[3] = { XSIZE_SUBDOMAIN, YSIZE_SUBDOMAIN, ZSIZE_SUBDOMAIN };

	int mycid[3];
	for(int c = 0; c < 3; ++c)
	    mycid[c] = L[c]/2 + (int)floor(p.x[c]);

	for(int c = 0; c < 3; ++c)
	    if (mycid[c] < -1 || mycid[c] >= L[c] + 1)
	    {
		for(int c = 0; c < 3; ++c)
		    accrbc[dpid].a[c] = 0;

		return;
	    }

	float fsum[3] = {0, 0, 0};

	for(int code = 0; code < 27; ++code)
	{
	    const int d[3] = {
		(code % 3) - 1,
		(code/3 % 3) - 1,
		(code/9 % 3) - 1
	    };

	    int vcid[3];
	    for(int c = 0; c < 3; ++c)
		vcid[c] = mycid[c] + d[c];

	    bool validcid = true;
	    for(int c = 0; c < 3; ++c)
		validcid &= vcid[c] >= 0 && vcid[c] < L[c];

	    if (!validcid)
		continue;

	    const int cid = vcid[0] + XSIZE_SUBDOMAIN * (vcid[1] + YSIZE_SUBDOMAIN * vcid[2]);
	    const int mystart = tex1Dfetch(texCellsStart, cid);
	    const int myend = mystart + tex1Dfetch(texCellsCount, cid);

	    assert(mystart >= 0 && mystart <= myend);
	    assert(myend <= npsolvent);

#pragma unroll 4
	    for(int s = mystart; s < myend; ++s)
	    {
		float f[3];
		const bool nonzero = fsi_kernel(seed, dpid, xp, up, s, f[0], f[1], f[2]);

		if (nonzero)
		{
		    for(int c = 0; c < 3; ++c)
			fsum[c] += f[c];

		    for(int c = 0; c < 3; ++c)
			atomicAdd(c + (float *)(accsolvent + s), -f[c]);
		}
	    }
	}

	for(int c = 0; c < 3; ++c)
	    accrbc[dpid].a[c] = fsum[c];
    }

    __constant__ int packstarts[27];
    __constant__ Particle * packstates[26];
    __constant__ Acceleration * packresults[26];

    template<int BLOCKSIZE> __global__  __launch_bounds__(32 * 4, 16)
	void fsi_forces_all(const float seed, Acceleration * accsolvent, const int npsolvent, const int nremote)
    {
	assert(blockDim.x == BLOCKSIZE);
	assert(blockDim.x * gridDim.x >= nremote);

	__shared__ float tmp[BLOCKSIZE * 3];

	const int tid = threadIdx.x;
	const int gidstart =  BLOCKSIZE * blockIdx.x;

	const int nlocal = min(BLOCKSIZE, nremote - gidstart);

	float3 xp, up;

#ifndef NDEBUG
	xp = make_float3(-313.313f, -313.313f, -313.313f); //che e' poi l'auto di paperino
	up = make_float3(-313.313f, -313.313f, -313.313f);
#endif

	{
	    const int n = nlocal * 6;
	    const int h = nlocal * 3;

	    for(int base = 0; base < n; base += h)
	    {
#pragma unroll 3
		for(int x = tid; x < h; x += BLOCKSIZE)
		{
		    const int l = base + x;
		    const int gid = gidstart + l / 6;

		    const int key9 = 9 * ((gid >= packstarts[9]) + (gid >= packstarts[18]));
		    const int key3 = 3 * ((gid >= packstarts[key9 + 3]) + (gid >= packstarts[key9 + 6]));
		    const int key1 = (gid >= packstarts[key9 + key3 + 1]) + (gid >= packstarts[key9 + key3 + 2]);

		    const int code = key9 + key3 + key1;
		    const int lpid = gid - packstarts[code];

		    assert(x < BLOCKSIZE * 3);
		    tmp[x] = *((l % 6) + (float *)&packstates[code][lpid]);
		}

		__syncthreads();

		const int xstart = tid * 6 - base;

		if (0 <= xstart && xstart + 3 <= h)
		{
		    xp.x = tmp[0 + xstart];
		    xp.y = tmp[1 + xstart];
		    xp.z = tmp[2 + xstart];

		    assert(0 + 6 * tid - base >= 0);
		    assert(2 + 6 * tid - base < 3 * BLOCKSIZE);
		}

		const int ustart = 3 + 6 * tid - base;

		if (0 <= ustart && ustart + 3 <= h)
		{
		    up.x = tmp[0 + ustart];
		    up.y = tmp[1 + ustart];
		    up.z = tmp[2 + ustart];

		    assert(3 + 6 * tid - base >= 0);
		    assert(5 + 6 * tid - base < 3 * BLOCKSIZE);
		}
	    }
	}

#ifndef NDEBUG
	assert(xp.x != -313.313f || gidstart + tid >= nremote);
	assert(xp.y != -313.313f || gidstart + tid >= nremote);
	assert(xp.z != -313.313f || gidstart + tid >= nremote);
	assert(up.x != -313.313f || gidstart + tid >= nremote);
	assert(up.y != -313.313f || gidstart + tid >= nremote);
	assert(up.z != -313.313f || gidstart + tid >= nremote);
#endif

	assert(!isnan(xp.x) && !isnan(xp.y) && !isnan(xp.z));
	assert(!isnan(up.x) && !isnan(up.y) && !isnan(up.z));

	__syncthreads();

	if (tid + gidstart < nremote)
	{
	    float fsum[3] = {0, 0, 0};

	    const int xcid = XSIZE_SUBDOMAIN / 2 + (int)floor(xp.x);
	    const int ycid = YSIZE_SUBDOMAIN / 2 + (int)floor(xp.y);
	    const int zcid = ZSIZE_SUBDOMAIN / 2 + (int)floor(xp.z);

	    const bool invalid =
		xcid < -1 || xcid >= XSIZE_SUBDOMAIN + 1 ||
		ycid < -1 || ycid >= YSIZE_SUBDOMAIN + 1 ||
		zcid < -1 || zcid >= ZSIZE_SUBDOMAIN + 1 ;

	    if (!invalid)
		for(int code = 0; code < 27; ++code)
		{
		    const int xsrccid = xcid + (code % 3) - 1;
		    const int ysrccid = ycid + (code/3 % 3) - 1;
		    const int zsrccid = zcid + (code/9 % 3) - 1;

		    const bool invalidsrccid =
			xsrccid < 0 || xsrccid >= XSIZE_SUBDOMAIN ||
			ysrccid < 0 || ysrccid >= YSIZE_SUBDOMAIN ||
			zsrccid < 0 || zsrccid >= ZSIZE_SUBDOMAIN ;

		    if (invalidsrccid)
			continue;

		    const int srccid = xsrccid + XSIZE_SUBDOMAIN * (ysrccid + YSIZE_SUBDOMAIN * zsrccid);

		    const int mystart = tex1Dfetch(texCellsStart, srccid);
		    const int myend = mystart + tex1Dfetch(texCellsCount, srccid);

		    assert(mystart >= 0 && mystart <= myend);
		    assert(myend <= npsolvent);

#pragma unroll 4
		    for(int s = mystart; s < myend; ++s)
		    {
			float f[3];
			const bool nonzero = fsi_kernel(seed, tid + gidstart, xp, up, s, f[0], f[1], f[2]);

			if (nonzero)
			{
			    for(int c = 0; c < 3; ++c)
				fsum[c] += f[c];

			    for(int c = 0; c < 3; ++c)
				atomicAdd(c + (float *)(accsolvent + s), -f[c]);
			}
		    }
		}

	    for(int c = 0; c < 3;  ++c)
		assert(!isnan(fsum[c]));

	    tmp[0 + 3 * tid] = fsum[0];
	    tmp[1 + 3 * tid] = fsum[1];
	    tmp[2 + 3 * tid] = fsum[2];
	}

	__syncthreads();

	{
	    const int n = nlocal * 3;

#pragma unroll 3
	    for(int l = tid; l < n; l += BLOCKSIZE)
	    {
		const int gid = gidstart + l / 3;

		const int key9 = 9 * ((gid >= packstarts[9]) + (gid >= packstarts[18]));
		const int key3 = 3 * ((gid >= packstarts[key9 + 3]) + (gid >= packstarts[key9 + 6]));
		const int key1 = (gid >= packstarts[key9 + key3 + 1]) + (gid >= packstarts[key9 + key3 + 2]);

		const int code = key9 + key3 + key1;
		const int lpid = gid - packstarts[code];

		packresults[code][lpid].a[l % 3] = tmp[l];
	    }
	}
    }

    __global__ void merge_accelerations(const Acceleration * const src, const int n, Acceleration * const dst)
    {
	const int gid = threadIdx.x + blockDim.x * blockIdx.x;

	if (gid < n)
	    for(int c = 0; c < 3; ++c)
		dst[gid].a[c] += src[gid].a[c];
    }

    __global__ void merge_accelerations_float(const Acceleration * const src, const int n, Acceleration * const dst)
    {
	assert(blockDim.x * gridDim.x >= n * 3);

	const int gid = threadIdx.x + blockDim.x * blockIdx.x;

	const int pid = gid / 3;
	const int c = gid % 3;

	if (pid < n)
	    dst[pid].a[c] += src[pid].a[c];
    }

    template<bool accumulation>
    __global__ void merge_accelerations_scattered_float(const int * const reordering, const Acceleration * const src,
							const int n, Acceleration * const dst)
    {
	assert(blockDim.x * gridDim.x >= n * 3);

	const int gid = threadIdx.x + blockDim.x * blockIdx.x;

	const int pid = gid / 3;
	const int c = gid % 3;

	if (pid < n)
	{
	    const int actualpid = reordering[pid];

	    if (accumulation)
		dst[actualpid].a[c] += src[pid].a[c];
	    else
		dst[actualpid].a[c] = src[pid].a[c];
	}
    }
}

ComputeInteractionsRBC::ComputeInteractionsRBC(MPI_Comm _cartcomm):
nvertices(0), dualcells(XSIZE_SUBDOMAIN, YSIZE_SUBDOMAIN, ZSIZE_SUBDOMAIN)
{
    assert(XSIZE_SUBDOMAIN % 2 == 0 && YSIZE_SUBDOMAIN % 2 == 0 && ZSIZE_SUBDOMAIN % 2 == 0);
    assert(XSIZE_SUBDOMAIN >= 2 && YSIZE_SUBDOMAIN >= 2 && ZSIZE_SUBDOMAIN >= 2);

    if (rbcs)
    {
	CudaRBC::Extent host_extent;
	CudaRBC::setup(nvertices, host_extent);
    }

    MPI_CHECK( MPI_Comm_dup(_cartcomm, &cartcomm));

    MPI_CHECK( MPI_Comm_rank(cartcomm, &myrank));

    local_trunk = Logistic::KISS(1908 - myrank, 1409 + myrank, 290, 12968);

    MPI_CHECK( MPI_Comm_size(cartcomm, &nranks));

    MPI_CHECK( MPI_Cart_get(cartcomm, 3, dims, periods, coords) );

    for(int i = 0; i < 26; ++i)
    {
	int d[3] = { (i + 2) % 3 - 1, (i / 3 + 2) % 3 - 1, (i / 9 + 2) % 3 - 1 };

	recv_tags[i] = (2 - d[0]) % 3 + 3 * ((2 - d[1]) % 3 + 3 * ((2 - d[2]) % 3));

	int coordsneighbor[3];
	for(int c = 0; c < 3; ++c)
	    coordsneighbor[c] = coords[c] + d[c];

	MPI_CHECK( MPI_Cart_rank(cartcomm, coordsneighbor, dstranks + i) );
    }

    KernelsRBC::ParamsFSI params = {12.5 , gammadpd, sigmaf};

    CUDA_CHECK(cudaMemcpyToSymbol(KernelsRBC::params, &params, sizeof(KernelsRBC::ParamsFSI)));

    CUDA_CHECK(cudaEventCreate(&evextents, cudaEventDisableTiming));
    CUDA_CHECK(cudaEventCreate(&evfsi, cudaEventDisableTiming));
}

void ComputeInteractionsRBC::_compute_extents(const Particle * const rbcs, const int nrbcs, cudaStream_t stream)
{
#if 1
    if (nrbcs)
	minmax_massimo(rbcs, nvertices, nrbcs, minextents.devptr, maxextents.devptr, stream);
#else
    for(int i = 0; i < nrbcs; ++i)
	CudaRBC::extent_nohost(stream, (float *)(rbcs + nvertices * i), extents.devptr + i);
#endif
}

void ComputeInteractionsRBC::extent(const Particle * const rbcs, const int nrbcs, cudaStream_t stream)
{
    NVTX_RANGE("RBC/extent", NVTX_C2);

    minextents.resize(nrbcs);
    maxextents.resize(nrbcs);

    _compute_extents(rbcs, nrbcs, stream);

    CUDA_CHECK(cudaEventRecord(evextents, stream));
}

void ComputeInteractionsRBC::count(const int nrbcs)
{
    NVTX_RANGE("RBC/count", NVTX_C3);

    CUDA_CHECK(cudaEventSynchronize(evextents));

    for(int i = 0; i < 26; ++i)
	haloreplica[i].clear();

    for(int i = 0; i < nrbcs; ++i)
    {
	float pmin[3] = { minextents.data[i].x, minextents.data[i].y, minextents.data[i].z };
	float pmax[3] = { maxextents.data[i].x, maxextents.data[i].y, maxextents.data[i].z };

	for(int code = 0; code < 26; ++code)
	{
	    const int L[3] = { XSIZE_SUBDOMAIN, YSIZE_SUBDOMAIN, ZSIZE_SUBDOMAIN };
	    const int d[3] = { (code + 2) % 3 - 1, (code / 3 + 2) % 3 - 1, (code / 9 + 2) % 3 - 1 };

	    bool interacting = true;

	    for(int c = 0; c < 3; ++c)
	    {
		const float range_start = max((float)(d[c] * L[c] - L[c]/2 - 1), pmin[c]);
		const float range_end = min((float)(d[c] * L[c] + L[c]/2 + 1), pmax[c]);

		interacting &= range_end > range_start;
	    }

	    if (interacting)
		haloreplica[code].push_back(i);
	}
    }

    for(int i = 0; i <26; ++i)
	MPI_CHECK(MPI_Irecv(recv_counts + i, 1, MPI_INTEGER, dstranks[i], recv_tags[i] + 2077, cartcomm, reqrecvcounts + i));


    for(int i = 0; i < 26; ++i)
    {
	send_counts[i] = haloreplica[i].size();
	MPI_CHECK(MPI_Isend(send_counts + i, 1, MPI_INTEGER, dstranks[i], i + 2077, cartcomm, reqsendcounts + i));
    }

    for(int i = 0; i < 26; ++i)
	local[i].setup(send_counts[i] * nvertices);
}

void ComputeInteractionsRBC::exchange_count()
{
    NVTX_RANGE("RBC/exchange-count", NVTX_C4);

    MPI_Status statuses[26];
    MPI_CHECK(MPI_Waitall(26, reqrecvcounts, statuses));
    MPI_CHECK(MPI_Waitall(26, reqsendcounts, statuses));

    for(int i = 0; i < 26; ++i)
	remote[i].setup(recv_counts[i] * nvertices);
}

void ComputeInteractionsRBC::pack_p(const Particle * const rbcs, cudaStream_t stream)
{
    NVTX_RANGE("RBC/pack", NVTX_C4);

#if 1
    {
	std::vector<int> codes;
	std::vector<const float *> src;
	std::vector<float *> dst;

	for(int i = 0; i < 26; ++i)
	    for(int j = 0; j < haloreplica[i].size(); ++j)
	    {
		codes.push_back(i);
		src.push_back((float *)(rbcs + nvertices * haloreplica[i][j]));
		dst.push_back((float *)(local[i].state.devptr + nvertices * j));
	    }

	KernelsRBC::shift_send_particles(stream, src.size(), nvertices, &src.front(), &codes.front(), &dst.front());

	CUDA_CHECK(cudaPeekAtLastError());
    }
#else
    for(int i = 0; i < 26; ++i)
    {
	for(int j = 0; j < haloreplica[i].size(); ++j)
	    KernelsRBC::shift_send_particles<<< (nvertices + 127) / 128, 128, 0, stream>>>
		(rbcs + nvertices * haloreplica[i][j], nvertices, i, local[i].state.devptr + nvertices * j);

	CUDA_CHECK(cudaPeekAtLastError());
    }
#endif

    CUDA_CHECK(cudaEventRecord(evfsi, stream));
}

void ComputeInteractionsRBC::post_p()
{
    NVTX_RANGE("RBC/post-p", NVTX_C5);

    CUDA_CHECK(cudaEventSynchronize(evfsi));

    for(int i = 0; i < 26; ++i)
	if (recv_counts[i] > 0)
	{
	    MPI_Request request;

	    MPI_CHECK(MPI_Irecv(remote[i].state.data, recv_counts[i] * nvertices, Particle::datatype(), dstranks[i],
				recv_tags[i] + 2011, cartcomm, &request));

	    reqrecvp.push_back(request);
	}

    for(int i = 0; i < 26; ++i)
	if (send_counts[i] > 0)
	{
	    MPI_Request request;

	    MPI_CHECK(MPI_Irecv(local[i].result.data, send_counts[i] * nvertices, Acceleration::datatype(), dstranks[i],
				recv_tags[i] + 2285, cartcomm, &request));

	    reqrecvacc.push_back(request);

	    MPI_CHECK(MPI_Isend(local[i].state.data, send_counts[i] * nvertices, Particle::datatype(), dstranks[i],
				i + 2011, cartcomm, &request));

	    reqsendp.push_back(request);
	}
}

void ComputeInteractionsRBC::internal_forces(const Particle * const rbcs, const int nrbcs, Acceleration * accrbc, cudaStream_t stream)
{
    CudaRBC::forces_nohost(stream, nrbcs, (float *)rbcs, (float *)accrbc);
}

void ComputeInteractionsRBC::fsi_bulk(const Particle * const solvent, const int nparticles, Acceleration * accsolvent,
				      const int * const cellsstart_solvent, const int * const cellscount_solvent,
				      const Particle * const rbcs, const int nrbcs, Acceleration * accrbc, cudaStream_t stream)
{
    NVTX_RANGE("RBC/fsi-bulk", NVTX_C6);

    KernelsRBC::setup(solvent, nparticles, cellsstart_solvent, cellscount_solvent);

    if (nrbcs > 0 && nparticles > 0)
    {
	const float seed = local_trunk.get_float();

#if 1
	const int nsolvent = nparticles;
	const int nsolute = nrbcs * nvertices;
	const int3 vcells = make_int3(XSIZE_SUBDOMAIN, YSIZE_SUBDOMAIN, ZSIZE_SUBDOMAIN);
	const int ncells = XSIZE_SUBDOMAIN * YSIZE_SUBDOMAIN * ZSIZE_SUBDOMAIN;

	reordered_solute.resize(nsolute);
	CUDA_CHECK(cudaMemcpyAsync(reordered_solute.data, rbcs, sizeof(Particle) * nrbcs * nvertices, cudaMemcpyDeviceToDevice, stream));

	reordering.resize(nsolute);
	dualcells.build(reordered_solute.data, nrbcs * nvertices, stream, reordering.data);

	texSoluteStart.acquire(const_cast<int *>(dualcells.start), ncells + 1);
	texSolute.acquire((float2 *)const_cast<Particle *>(reordered_solute.data), reordered_solute.capacity);

	lacc_solute.resize(nsolute);
	CUDA_CHECK(cudaMemsetAsync(lacc_solute.data, 0, sizeof(float) * 3 * lacc_solute.size, stream));

	KernelsRBC::fsi_forces<2, 2, 1, 32, 1><<<
	    dim3(vcells.x / 2, vcells.y / 2, vcells.z), dim3(32, 4), 0, stream>>>
	    (seed, texSoluteStart.texObj, texSolute.texObj, (float *)lacc_solute.data, lacc_solute.size, (float *)accsolvent, nsolvent);

        KernelsRBC::merge_accelerations_scattered_float<false><<< (nrbcs * nvertices * 3 + 127) / 128, 128, 0, stream >>>(
	    reordering.data, lacc_solute.data, nrbcs * nvertices, accrbc);

#else
	KernelsRBC::fsi_forces<<< (nrbcs * nvertices + 127) / 128, 128, 0, stream >>>
	    (seed, accsolvent, nparticles, rbcs, nrbcs * nvertices, accrbc);
#endif
    }
}

void ComputeInteractionsRBC::fsi_halo(const Particle * const solvent, const int nparticles, Acceleration * accsolvent,
				      const int * const cellsstart_solvent, const int * const cellscount_solvent,
				      const Particle * const rbcs, const int nrbcs, Acceleration * accrbc, cudaStream_t stream)
{
    NVTX_RANGE("RBC/fsi-halo", NVTX_C7);

    _wait(reqrecvp);
    _wait(reqsendp);

#if 1
    {
	int nremote = 0;

	{
	    int packstarts[27];

	    packstarts[0] = 0;
	    for(int i = 0, s = 0; i < 26; ++i)
		packstarts[i + 1] = (s += remote[i].state.size);

	    nremote = packstarts[26];

	    CUDA_CHECK(cudaMemcpyToSymbolAsync(KernelsRBC::packstarts, packstarts,
					       sizeof(packstarts), 0, cudaMemcpyHostToDevice, stream));
	}

	{
	    Particle * packstates[26];

	    for(int i = 0; i < 26; ++i)
		packstates[i] = remote[i].state.devptr;

	    CUDA_CHECK(cudaMemcpyToSymbolAsync(KernelsRBC::packstates, packstates,
					       sizeof(packstates), 0, cudaMemcpyHostToDevice, stream));
	}

	{
	    Acceleration * packresults[26];

	    for(int i = 0; i < 26; ++i)
		packresults[i] = remote[i].result.devptr;

	    CUDA_CHECK(cudaMemcpyToSymbolAsync(KernelsRBC::packresults, packresults,
					       sizeof(packresults), 0, cudaMemcpyHostToDevice, stream));
	}

	if(nremote)
	    KernelsRBC::fsi_forces_all<128><<< (nremote + 127) / 128, 128, 0, stream>>>(local_trunk.get_float(), accsolvent, nparticles, nremote);

    }
#else
    for(int i = 0; i < 26; ++i)
    {
	const int count = remote[i].state.size;

	if (count > 0)
	    KernelsRBC::fsi_forces<<< (count + 127) / 128, 128, 0, stream >>>
		(local_trunk.get_float(), accsolvent, nparticles, remote[i].state.devptr, count, remote[i].result.devptr);
    }
#endif

    CUDA_CHECK(cudaEventRecord(evfsi));

    CUDA_CHECK(cudaPeekAtLastError());
}

void ComputeInteractionsRBC::post_a()
{
    NVTX_RANGE("RBC/send-results", NVTX_C1);

    CUDA_CHECK(cudaEventSynchronize(evfsi));

    _wait(reqsendacc);

    for(int i = 0; i < 26; ++i)
	if (recv_counts[i] > 0)
	{
	    MPI_Request request;

	    MPI_CHECK(MPI_Isend(remote[i].result.data, recv_counts[i] * nvertices, Acceleration::datatype(), dstranks[i],
				i + 2285, cartcomm, &request));

	    reqsendacc.push_back(request);
	}
}

void ComputeInteractionsRBC::merge_a(Acceleration * accrbc, cudaStream_t stream)
{
    NVTX_RANGE("RBC/merge", NVTX_C2);

    _wait(reqrecvacc);

#if 1
    {
	std::vector<const float *> src;
	std::vector<float *> dst;

	for(int i = 0; i < 26; ++i)
	    for(int j = 0; j < haloreplica[i].size(); ++j)
	    {
		src.push_back((float *)(local[i].result.devptr + nvertices * j));
		dst.push_back((float *)(accrbc + nvertices * haloreplica[i][j]));
	    }

	KernelsRBC::merge_all_accel(stream, src.size(), nvertices, &src.front(), &dst.front());

	CUDA_CHECK(cudaPeekAtLastError());
    }
#else
    for(int i = 0; i < 26; ++i)
	for(int j = 0; j < haloreplica[i].size(); ++j)
	    KernelsRBC::merge_accelerations<<< (nvertices + 127) / 128, 128, 0, stream>>>(local[i].result.devptr + nvertices * j, nvertices,
											  accrbc + nvertices * haloreplica[i][j]);
#endif
}

ComputeInteractionsRBC::~ComputeInteractionsRBC()
{
    MPI_CHECK(MPI_Comm_free(&cartcomm));

    CUDA_CHECK(cudaEventDestroy(evextents));
    CUDA_CHECK(cudaEventDestroy(evfsi));

    KernelsRBC::dispose();
}

