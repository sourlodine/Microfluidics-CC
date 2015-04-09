/*
 *  cuda-dpd.cu
 *  Part of CTC/cuda-dpd-sem/dpd/
 *
 *  Evaluation of DPD force using Newton's 3rd law
 *  Created and authored by Yu-Hang Tang and Mauro Bisson on 2015-04-01.
 *  Copyright 2015. All rights reserved.
 *
 *  Users are NOT authorized
 *  to employ the present software for their own publications
 *  before getting a written permission from the author of this file.
 */

#include <cstdio>
#include <cassert>

#include "cuda-dpd.h"
#include "../dpd-rng.h"

struct InfoDPD
{
    int3 ncells;
    float3 domainsize, invdomainsize, domainstart;
    float invrc, aij, gamma, sigmaf;
    float * axayaz;
    float seed;
    // YTANG testing
    float4 *xyzo;
};

__constant__ InfoDPD info;

texture<float2, cudaTextureType1D> texParticles2;
texture<float4, cudaTextureType1D> texParticlesF4;
texture<ushort4, cudaTextureType1D, cudaReadModeNormalizedFloat> texParticlesH4;
texture<int, cudaTextureType1D> texStart, texCount;
 
#define _XCPB_ 2
#define _YCPB_ 2
#define _ZCPB_ 1
#define CPB (_XCPB_ * _YCPB_ * _ZCPB_)

__device__ float3 _dpd_interaction(const int dpid, const float3 xdest, const float3 udest, const float3 xsrc, const float3 usrc, const int spid)
{
    const float _xr = xdest.x - xsrc.x;
    const float _yr = xdest.y - xsrc.y;
    const float _zr = xdest.z - xsrc.z;

    const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;
    assert(rij2 < 1);

    const float invrij = rsqrtf(rij2);
    const float rij = rij2 * invrij;
    const float argwr = 1 - rij;
    const float wr = viscosity_function<-VISCOSITY_S_LEVEL>(argwr);

    const float xr = _xr * invrij;
    const float yr = _yr * invrij;
    const float zr = _zr * invrij;

    const float rdotv =
	xr * (udest.x - usrc.x) +
	yr * (udest.y - usrc.y) +
	zr * (udest.z - usrc.z);

    const float myrandnr = Logistic::mean0var1(info.seed, min(spid, dpid), max(spid, dpid));

    const float strength = info.aij * argwr - (info.gamma * wr * rdotv + info.sigmaf * myrandnr) * wr;

    return make_float3(strength * xr, strength * yr, strength * zr);
}

__device__ float3 _dpd_interaction(const int dpid, const float4 xdest, const float4 udest, const float4 xsrc, const float4 usrc, const int spid)
{
    const float _xr = xdest.x - xsrc.x;
    const float _yr = xdest.y - xsrc.y;
    const float _zr = xdest.z - xsrc.z;

    const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;
    assert(rij2 < 1);

    const float invrij = rsqrtf(rij2);
    const float rij = rij2 * invrij;
    const float argwr = 1 - rij;
    const float wr = viscosity_function<-VISCOSITY_S_LEVEL>(argwr);

    const float xr = _xr * invrij;
    const float yr = _yr * invrij;
    const float zr = _zr * invrij;

    const float rdotv =
	xr * (udest.x - usrc.x) +
	yr * (udest.y - usrc.y) +
	zr * (udest.z - usrc.z);

    const float myrandnr = Logistic::mean0var1(info.seed, min(spid, dpid), max(spid, dpid));

    const float strength = info.aij * argwr - (info.gamma * wr * rdotv + info.sigmaf * myrandnr) * wr;

    return make_float3(strength * xr, strength * yr, strength * zr);
}

#define __IMOD(x,y) ((x)-((x)/(y))*(y))

__inline__ __device__ uint __lanemask_lt() {
	uint mask;
	asm("mov.u32 %0, %lanemask_lt;" : "=r"(mask) );
	return mask;
}

__inline__ __device__ uint __pack_8_24(uint a, uint b) {
	uint d;
	asm("bfi.b32  %0, %1, %2, 24, 8;" : "=r"(d) : "r"(a), "r"(b) );
	return d;
}

__inline__ __device__ uint2 __unpack_8_24(uint d) {
	uint a;
	asm("bfe.u32  %0, %1, 24, 8;" : "=r"(a) : "r"(d) );
	return make_uint2( a, d&0x00FFFFFFU );
}


#define TRANSPOSED_ATOMICS
//#define ONESTEP
#define LETS_MAKE_IT_MESSY
#define HALF_FLOAT
//#define CONSOLIDATE_SMEM
//#define DIRECT_LD

__device__ char4 tid2ind[14] = {{-1, -1, -1, 0}, {0, -1, -1, 0}, {1, -1, -1, 0},
				{-1,  0, -1, 0}, {0,  0, -1, 0}, {1,  0, -1, 0},
				{-1,  1, -1, 0}, {0,  1, -1, 0}, {1,  1, -1, 0},
				{-1, -1,  0, 0}, {0, -1,  0, 0}, {1, -1,  0, 0},
				{-1,  0,  0, 0}, {0,  0,  0, 0}};
#define MYCPBX	(4)
#define MYCPBY	(2)
#define MYCPBZ	(2)
#define MYWPB	(4)

//__forceinline__ __device__ void core_ytang1(uint volatile queue[MYWPB][64], const uint dststart, const uint wid, const uint tid, const uint spidext ) {
//	const uint2 pid = __unpack_8_24( queue[wid][tid] );
//	const uint dpid = dststart + pid.x;
//	const uint spid = pid.y;
//
//	#ifdef LETS_MAKE_IT_MESSY
//	const float4 xdest = tex1Dfetch(texParticlesF4, xscale( dpid, 2.f     ) );
//	const float4 udest = tex1Dfetch(texParticlesF4,   xmad( dpid, 2.f, 1u ) );
//	const float4 xsrc  = tex1Dfetch(texParticlesF4, xscale( spid, 2.f     ) );
//	const float4 usrc  = tex1Dfetch(texParticlesF4,   xmad( spid, 2.f, 1u ) );
//	#else
//	const uint sentry = xscale( spid, 3.f );
//	const float2 stmp0 = tex1Dfetch(texParticles2, sentry    );
//	const float2 stmp1 = tex1Dfetch(texParticles2, xadd( sentry, 1u ) );
//	const float2 stmp2 = tex1Dfetch(texParticles2, xadd( sentry, 2u ) );
//	const float3 xsrc = make_float3( stmp0.x, stmp0.y, stmp1.x );
//	const float3 usrc = make_float3( stmp1.y, stmp2.x, stmp2.y );
//	const uint dentry = xscale( dpid, 3.f );
//	const float2 dtmp0 = tex1Dfetch(texParticles2, dentry    );
//	const float2 dtmp1 = tex1Dfetch(texParticles2, xadd( dentry, 1u ) );
//	const float2 dtmp2 = tex1Dfetch(texParticles2, xadd( dentry, 2u ) );
//	const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
//	const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );
//	#endif
//	const float3 f = _dpd_interaction(dpid, xdest, udest, xsrc, usrc, spid);
//
//	// the overhead of transposition acc back
//	// can be completely killed by changing the integration kernel
//	#ifdef TRANSPOSED_ATOMICS
//	uint base = dpid & 0xFFFFFFE0U;
//	uint off  = xsub( dpid, base );
//	float* acc = info.axayaz + xmad( base, 3.f, off );
//	atomicAdd(acc   , f.x);
//	atomicAdd(acc+32, f.y);
//	atomicAdd(acc+64, f.z);
//
//	if (spid < spidext) {
//		uint base = spid & 0xFFFFFFE0U;
//		uint off  = xsub( spid, base );
//		float* acc = info.axayaz + xmad( base, 3.f, off );
//		atomicAdd(acc   , -f.x);
//		atomicAdd(acc+32, -f.y);
//		atomicAdd(acc+64, -f.z);
//	}
//	#else
//	float* acc = info.axayaz + xscale( dpid, 3.f );
//	atomicAdd(acc  , f.x);
//	atomicAdd(acc+1, f.y);
//	atomicAdd(acc+2, f.z);
//
//	if (spid < spidext) {
//		float* acc = info.axayaz + xscale( spid, 3.f );
//		atomicAdd(acc  , -f.x);
//		atomicAdd(acc+1, -f.y);
//		atomicAdd(acc+2, -f.z);
//	}
//	#endif
//}

__global__  __launch_bounds__(32*MYWPB, 16)
void _dpd_forces_new5() {

	__shared__ uint2 volatile start_n_scan[MYWPB][32];
	__shared__ uint  volatile queue[MYWPB][64];

	const uint tid = threadIdx.x;
	const uint wid = threadIdx.y;

	const char4 offs = __ldg(tid2ind+tid);
	const int cbase = blockIdx.z*MYCPBZ*info.ncells.x*info.ncells.y +
                          blockIdx.y*MYCPBY*info.ncells.x +
                          blockIdx.x*MYCPBX + wid +
			  offs.z*info.ncells.x*info.ncells.y +
			  offs.y*info.ncells.x +
			  offs.x;

	//#pragma unroll 4 // faster on k20x, slower on k20
	for(int it = 3; it >= 0; it--) {

		uint mycount=0, myscan=0;

		if (tid < 14) {
			const int cid = cbase +
					(it>1)*info.ncells.x*info.ncells.y +
					((it&1)^((it>>1)&1))*info.ncells.x;

			const bool valid_cid = (cid >= 0) && (cid < info.ncells.x*info.ncells.y*info.ncells.z);

			start_n_scan[wid][tid].x = (valid_cid) ? tex1Dfetch(texStart, cid) : 0;
			myscan = mycount = (valid_cid) ? tex1Dfetch(texCount, cid) : 0;
		}
	   
		#pragma unroll 
		for(int L = 1; L < 32; L <<= 1)
			myscan += (tid >= L)*__shfl_up(myscan, L);

		if (tid < 15) start_n_scan[wid][tid].y = myscan - mycount;
	    
		const uint dststart = start_n_scan[wid][13].x;
		const uint lastdst  = xsub( xadd( dststart, start_n_scan[wid][14].y ), start_n_scan[wid][13].y );

		const uint nsrc     = start_n_scan[wid][14].y;
		const uint spidext  = start_n_scan[wid][13].x;

		#ifdef CONSOLIDATE_SMEM
		// 0 3 6 9 12 15
//		if (tid < 7) {
//			uint d = min( tid * 3, 14 );
//			start_n_scan[wid][tid].x = start_n_scan[wid][d].x;
//			start_n_scan[wid][tid].y = start_n_scan[wid][d].y;
//		}
		if (tid==15) {
			start_n_scan[wid][tid].x = start_n_scan[wid][14].x;
			start_n_scan[wid][tid].y = start_n_scan[wid][14].y;
		}
		#endif

		// TODO
		uint nb = 0;
		for(uint p = 0; p < nsrc; p = xadd( p, 32u ) ) {
			const uint pid = p + tid;
			#if 0//def LETS_MAKE_IT_MESSY
			uint spid;
			asm( "{ .reg .pred p, q, r;"
				 "  .reg .f32  key;"
				 "  .reg .f32  scan3, scan6, scan9;"
				 "  .reg .f32  mystart, myscan;"
				 "  .reg .s32  array;"
				 "  .reg .f32  array_f;"
				 "   mov.b32           array_f, %4;"
				 "   mul.f32           array_f, array_f, 256.0;"
				 "   mov.b32           array, array_f;"
				 "   ld.shared.f32     scan9,  [array +  9*8 + 4];"
				 "   setp.ge.f32       p, %1, scan9;"
				 "   selp.f32          key, %2, 0.0, p;"
				 "   mov.b32           array_f, array;"
				 "   fma.f32.rm        array_f, key, 8.0, array_f;"
				 "   mov.b32 array,    array_f;"
				 "   ld.shared.f32     scan3, [array + 3*8 + 4];"
				 "   setp.ge.f32       p, %1, scan3;"
				 "@p add.f32           key, key, %3;"
				 "   setp.lt.f32       p, key, %2;"
				 "   setp.lt.and.f32   p, %5, %6, p;"
				 "@p ld.shared.f32     scan6, [array + 6*8 + 4];"
				 "   setp.ge.and.f32   q, %1, scan6, p;"
				 "@q add.f32           key, key, %3;"
				 "   mov.b32           array_f, %4;"
				 "   mul.f32           array_f, array_f, 256.0;"
				 "   fma.f32.rm        array_f, key, 8.0, array_f;"
				 "   mov.b32           array, array_f;"
				 "   ld.shared.v2.f32 {mystart, myscan}, [array];"
				 "   add.f32           mystart, mystart, %1;"
				 "   sub.f32           mystart, mystart, myscan;"
				 "   mov.b32           %0, mystart;"
				 "}" : "=r"(spid) : "f"(u2f(pid)), "f"(u2f(9u)), "f"(u2f(3u)), "f"(u2f(wid)), "f"(u2f(pid)), "f"(u2f(nsrc)) );
			#else
			#ifdef CONSOLIDATE_SMEM
			const uint key9 = 9*(pid >= start_n_scan[wid][9].y);
			const uint key3 = 3*((pid >= start_n_scan[wid][key9 + 3].y)+(pid >= start_n_scan[wid][key9 + 6].y));
			const uint spid = pid - start_n_scan[wid][key3+key9].y + start_n_scan[wid][key3+key9].x;
			#else
			const uint key9 = 9*(pid >= start_n_scan[wid][9].y);
			uint key3 = 3*(pid >= start_n_scan[wid][key9 + 3].y);
			key3 += (key9 < 9) ? 3*(pid >= start_n_scan[wid][key9 + 6].y) : 0;
			const uint spid = pid - start_n_scan[wid][key3+key9].y + start_n_scan[wid][key3+key9].x;
			#endif
			#endif

			#ifdef LETS_MAKE_IT_MESSY
			float4 xsrc;
			#else
			float3 xsrc;
			#endif

			if (pid<nsrc) {
				#ifdef LETS_MAKE_IT_MESSY
				#ifdef HALF_FLOAT
				xsrc = tex1Dfetch(texParticlesH4, spid );
				#else
				#ifdef DIRECT_LD
				xsrc = info.xyzo[spid];
				#else
				xsrc = tex1Dfetch(texParticlesF4, xscale( spid, 2.f ) );
				#endif
				#endif
				#else
				const uint sentry = xscale( spid, 3.f );
				const float2 stmp0 = tex1Dfetch(texParticles2, sentry    );
				const float2 stmp1 = tex1Dfetch(texParticles2, xadd( sentry, 1u ) );
				xsrc = make_float3( stmp0.x, stmp0.y, stmp1.x );
				#endif
			}

			for(uint dpid = dststart; dpid < lastdst; dpid = xadd(dpid, 1u) ) {
				int interacting = 0;
				if (pid<nsrc) {
					#ifdef LETS_MAKE_IT_MESSY
					#ifdef HALF_FLOAT
					const float4 xdest = tex1Dfetch(texParticlesH4, dpid );
					#else
					#ifdef DIRECT_LD
					const float4 xdest = info.xyzo[dpid];
					#else
					const float4 xdest = tex1Dfetch(texParticlesF4, xscale( dpid, 2.f ) );
					#endif
					#endif
					#else
					const uint dentry = xscale( dpid, 3.f );
					const float2 dtmp0 = tex1Dfetch(texParticles2,      dentry      );
					const float2 dtmp1 = tex1Dfetch(texParticles2, xadd(dentry, 1u ));
					const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
					#endif

					const float d2 = (xdest.x-xsrc.x)*(xdest.x-xsrc.x) + (xdest.y-xsrc.y)*(xdest.y-xsrc.y) + (xdest.z-xsrc.z)*(xdest.z-xsrc.z);
					#ifdef LETS_MAKE_IT_MESSY
					asm("{ .reg .pred        p;"
						"  .reg .f32         i;"
						"   setp.lt.ftz.f32  p, %3, 1.0;"
						"   setp.ne.and.f32  p, %1, %2, p;"
						"   selp.s32         %0, 1, 0, p;"
						"}" : "+r"(interacting) : "f"(u2f(dpid)), "f"(u2f(spid)), "f"(d2), "f"(u2f(1u)) );
					#else
					interacting = ((dpid != spid) && (d2 < 1.0f));
					#endif
				}

				uint overview = __ballot( interacting );
				const uint insert = xadd( nb, i2u( __popc( overview & __lanemask_lt() ) ) );
				if (interacting) queue[wid][insert] = __pack_8_24( xsub(dpid,dststart), spid );
				nb = xadd( nb, i2u( __popc( overview ) ) );
				if ( nb >= 32u ) {
					const uint2 pid = __unpack_8_24( queue[wid][tid] );
					const uint dpid = dststart + pid.x;
					const uint spid = pid.y;

					#ifdef LETS_MAKE_IT_MESSY
					const float4 xdest = tex1Dfetch(texParticlesF4, xscale( dpid, 2.f     ) );
					const float4 udest = tex1Dfetch(texParticlesF4,   xmad( dpid, 2.f, 1u ) );
					const float4 xsrc  = tex1Dfetch(texParticlesF4, xscale( spid, 2.f     ) );
					const float4 usrc  = tex1Dfetch(texParticlesF4,   xmad( spid, 2.f, 1u ) );
					#else
					const uint sentry = xscale( spid, 3.f );
					const float2 stmp0 = tex1Dfetch(texParticles2, sentry    );
					const float2 stmp1 = tex1Dfetch(texParticles2, xadd( sentry, 1u ) );
					const float2 stmp2 = tex1Dfetch(texParticles2, xadd( sentry, 2u ) );
					const float3 xsrc = make_float3( stmp0.x, stmp0.y, stmp1.x );
					const float3 usrc = make_float3( stmp1.y, stmp2.x, stmp2.y );
					const uint dentry = xscale( dpid, 3.f );
					const float2 dtmp0 = tex1Dfetch(texParticles2, dentry    );
					const float2 dtmp1 = tex1Dfetch(texParticles2, xadd( dentry, 1u ) );
					const float2 dtmp2 = tex1Dfetch(texParticles2, xadd( dentry, 2u ) );
					const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
					const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );
					#endif
					const float3 f = _dpd_interaction(dpid, xdest, udest, xsrc, usrc, spid);

					// the overhead of transposition acc back
					// can be completely killed by changing the integration kernel
					#ifdef TRANSPOSED_ATOMICS
					uint base = dpid & 0xFFFFFFE0U;
					uint off  = xsub( dpid, base );
					float* acc = info.axayaz + xmad( base, 3.f, off );
					atomicAdd(acc   , f.x);
					atomicAdd(acc+32, f.y);
					atomicAdd(acc+64, f.z);

					if (spid < spidext) {
						uint base = spid & 0xFFFFFFE0U;
						uint off  = xsub( spid, base );
						float* acc = info.axayaz + xmad( base, 3.f, off );
						atomicAdd(acc   , -f.x);
						atomicAdd(acc+32, -f.y);
						atomicAdd(acc+64, -f.z);
					}
					#else
					float* acc = info.axayaz + xscale( dpid, 3.f );
					atomicAdd(acc  , f.x);
					atomicAdd(acc+1, f.y);
					atomicAdd(acc+2, f.z);

					if (spid < spidext) {
						float* acc = info.axayaz + xscale( spid, 3.f );
						atomicAdd(acc  , -f.x);
						atomicAdd(acc+1, -f.y);
						atomicAdd(acc+2, -f.z);
					}
					#endif

					nb = xsub( nb, 32u );
					queue[wid][tid] = queue[wid][tid+32];
				}
			}
		}

		if (tid < nb) {
			const uint2 pid = __unpack_8_24( queue[wid][tid] );
			const uint dpid = dststart + pid.x;
			const uint spid = pid.y;

			#ifdef LETS_MAKE_IT_MESSY
			const float4 xdest = tex1Dfetch(texParticlesF4, xscale( dpid, 2.f     ) );
			const float4 udest = tex1Dfetch(texParticlesF4,   xmad( dpid, 2.f, 1u ) );
			const float4 xsrc  = tex1Dfetch(texParticlesF4, xscale( spid, 2.f     ) );
			const float4 usrc  = tex1Dfetch(texParticlesF4,   xmad( spid, 2.f, 1u ) );
			#else
			const uint sentry = xscale( spid, 3.f );
			const float2 stmp0 = tex1Dfetch(texParticles2, sentry    );
			const float2 stmp1 = tex1Dfetch(texParticles2, xadd( sentry, 1u ) );
			const float2 stmp2 = tex1Dfetch(texParticles2, xadd( sentry, 2u ) );
			const float3 xsrc = make_float3( stmp0.x, stmp0.y, stmp1.x );
			const float3 usrc = make_float3( stmp1.y, stmp2.x, stmp2.y );
			const uint dentry = xscale( dpid, 3.f );
			const float2 dtmp0 = tex1Dfetch(texParticles2, dentry    );
			const float2 dtmp1 = tex1Dfetch(texParticles2, xadd( dentry, 1u ) );
			const float2 dtmp2 = tex1Dfetch(texParticles2, xadd( dentry, 2u ) );
			const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
			const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );
			#endif
			const float3 f = _dpd_interaction(dpid, xdest, udest, xsrc, usrc, spid);

			// the overhead of transposition acc back
			// can be completely killed by changing the integration kernel
			#ifdef TRANSPOSED_ATOMICS
			uint base = dpid & 0xFFFFFFE0U;
			uint off  = xsub( dpid, base );
			float* acc = info.axayaz + xmad( base, 3.f, off );
			atomicAdd(acc   , f.x);
			atomicAdd(acc+32, f.y);
			atomicAdd(acc+64, f.z);

			if (spid < spidext) {
				uint base = spid & 0xFFFFFFE0U;
				uint off  = xsub( spid, base );
				float* acc = info.axayaz + xmad( base, 3.f, off );
				atomicAdd(acc   , -f.x);
				atomicAdd(acc+32, -f.y);
				atomicAdd(acc+64, -f.z);
			}
			#else
			float* acc = info.axayaz + xscale( dpid, 3.f );
			atomicAdd(acc  , f.x);
			atomicAdd(acc+1, f.y);
			atomicAdd(acc+2, f.z);

			if (spid < spidext) {
				float* acc = info.axayaz + xscale( spid, 3.f );
				atomicAdd(acc  , -f.x);
				atomicAdd(acc+1, -f.y);
				atomicAdd(acc+2, -f.z);
			}
			#endif
		}
		nb = 0;
	}
}

bool fdpd_init = false;

#include "../hacks.h"
#ifdef _TIME_PROFILE_
static cudaEvent_t evstart, evstop;
#endif

__global__ void make_texture( float4 *xyzouvwo, float4 *xyzo, ushort4 *xyzo_half, const float *xyzuvw, const int n ) {
	for(int i=blockIdx.x*blockDim.x+threadIdx.x;i<n;i+=blockDim.x*gridDim.x) {
		float x = xyzuvw[i*6+0];
		float y = xyzuvw[i*6+1];
		float z = xyzuvw[i*6+2];
		float u = xyzuvw[i*6+3];
		float v = xyzuvw[i*6+4];
		float w = xyzuvw[i*6+5];
		xyzouvwo[i*2+0] = make_float4( x, y, z, 0.f );
		xyzouvwo[i*2+1] = make_float4( u, v, w, 0.f );
		xyzo[i] = make_float4( x, y, z, 0.f );
		xyzo_half[i] = make_ushort4( __float2half_rn(x), __float2half_rn(y), __float2half_rn(z), 0 );
	}
}

__global__ void check_acc(const int np)
{
	double sx = 0, sy = 0, sz = 0;
	for(int i=0;i<np;i++) {
		sx += info.axayaz[i*3+0];
		sy += info.axayaz[i*3+1];
		sz += info.axayaz[i*3+2];
	}
	printf("ACC: %lf %lf %lf\n",sx,sy,sz);
}

__global__ void transpose_acc(const int np)
{
	for(int i=blockIdx.x*blockDim.x+threadIdx.x;i<np;i+=blockDim.x*gridDim.x) {
		int base = i & 0xFFFFFFE0U;
		int off  = i - base;
		float ax = info.axayaz[ base*3 + off      ];
		float ay = info.axayaz[ base*3 + off + 32 ];
		float az = info.axayaz[ base*3 + off + 64 ];
		// make sync between lanes
		if (__ballot(1)) {
			info.axayaz[ i * 3 + 0 ] = ax;
			info.axayaz[ i * 3 + 1 ] = ay;
			info.axayaz[ i * 3 + 2 ] = az;
		}
	}
}

void forces_dpd_cuda_nohost(const float * const xyzuvw, float * const axayaz,  const int np,
			    const int * const cellsstart, const int * const cellscount, 
			    const float rc,
			    const float XL, const float YL, const float ZL,
			    const float aij,
			    const float gamma,
			    const float sigma,
			    const float invsqrtdt,
			    const float seed, cudaStream_t stream)
{
    if (np == 0)
    {
	printf("WARNING: forces_dpd_cuda_nohost called with np = %d\n", np);
	return;
    }

    int nx = (int)ceil(XL / rc);
    int ny = (int)ceil(YL / rc);
    int nz = (int)ceil(ZL / rc);
    const int ncells = nx * ny * nz;

    if (!fdpd_init)
    {
	texStart.channelDesc = cudaCreateChannelDesc<int>();
	texStart.filterMode = cudaFilterModePoint;
	texStart.mipmapFilterMode = cudaFilterModePoint;
	texStart.normalized = 0;
    
	texCount.channelDesc = cudaCreateChannelDesc<int>();
	texCount.filterMode = cudaFilterModePoint;
	texCount.mipmapFilterMode = cudaFilterModePoint;
	texCount.normalized = 0;

	texParticles2.channelDesc = cudaCreateChannelDesc<float2>();
	texParticles2.filterMode = cudaFilterModePoint;
	texParticles2.mipmapFilterMode = cudaFilterModePoint;
	texParticles2.normalized = 0;

	texParticlesF4.channelDesc = cudaCreateChannelDesc<float4>();
	texParticlesF4.filterMode = cudaFilterModePoint;
	texParticlesF4.mipmapFilterMode = cudaFilterModePoint;
	texParticlesF4.normalized = 0;

	texParticlesH4.channelDesc = cudaCreateChannelDescHalf4();
	texParticlesH4.filterMode = cudaFilterModePoint;
	texParticlesH4.mipmapFilterMode = cudaFilterModePoint;
	texParticlesH4.normalized = 0;

	CUDA_CHECK(cudaFuncSetCacheConfig(_dpd_forces_new5, cudaFuncCachePreferEqual));

#ifdef _TIME_PROFILE_
	CUDA_CHECK(cudaEventCreate(&evstart));
	CUDA_CHECK(cudaEventCreate(&evstop));
#endif
	fdpd_init = true;
    }

    InfoDPD c;

    size_t textureoffset;
	#ifdef LETS_MAKE_IT_MESSY
	static float4 *xyzouvwo, *xyzo;
	static ushort4 *xyzo_half;
	static int last_size;
	if (!xyzouvwo || last_size < np ) {
			if (xyzouvwo) {
				cudaFree( xyzouvwo );
				cudaFree( xyzo );
				cudaFree( xyzo_half );
			}
			cudaMalloc( &xyzouvwo,  sizeof(float4)*2*np);
			cudaMalloc( &xyzo,      sizeof(float4)*np);
			cudaMalloc( &xyzo_half, sizeof(ushort4)*np);
			last_size = np;
	}
	make_texture<<<64,512,0,stream>>>( xyzouvwo, xyzo, xyzo_half, xyzuvw, np );
	CUDA_CHECK( cudaBindTexture( &textureoffset, &texParticlesF4, xyzouvwo,  &texParticlesF4.channelDesc, sizeof( float ) * 8 * np ) );
	CUDA_CHECK( cudaBindTexture( &textureoffset, &texParticlesH4, xyzo_half, &texParticlesH4.channelDesc, sizeof( ushort4 ) * np ) );
	c.xyzo = xyzo;
	assert(textureoffset == 0);
	#else
	CUDA_CHECK(cudaBindTexture(&textureoffset, &texParticles2, xyzuvw, &texParticles2.channelDesc, sizeof(float) * 6 * np));
    assert(textureoffset == 0);
	#endif
    CUDA_CHECK(cudaBindTexture(&textureoffset, &texStart, cellsstart, &texStart.channelDesc, sizeof(int) * ncells));
    assert(textureoffset == 0);
    CUDA_CHECK(cudaBindTexture(&textureoffset, &texCount, cellscount, &texCount.channelDesc, sizeof(int) * ncells));
    assert(textureoffset == 0);
      
    c.ncells = make_int3(nx, ny, nz);
    c.domainsize = make_float3(XL, YL, ZL);
    c.invdomainsize = make_float3(1 / XL, 1 / YL, 1 / ZL);
    c.domainstart = make_float3(-XL * 0.5, -YL * 0.5, -ZL * 0.5);
    c.invrc = 1.f / rc;
    c.aij = aij;
    c.gamma = gamma;
    c.sigmaf = sigma * invsqrtdt;
    c.axayaz = axayaz;
    c.seed = seed;
      
    CUDA_CHECK(cudaMemcpyToSymbolAsync(info, &c, sizeof(c), 0, cudaMemcpyHostToDevice, stream));
   
    static int cetriolo = 0;
    cetriolo++;

#ifdef _TIME_PROFILE_
    if (cetriolo % 500 == 0)
	CUDA_CHECK(cudaEventRecord(evstart));
#endif

    // YUHANG: fixed bug: not using stream
    CUDA_CHECK( cudaMemsetAsync(axayaz, 0, sizeof(float)*np*3, stream) );

    if (c.ncells.x%MYCPBX==0 && c.ncells.y%MYCPBY==0 && c.ncells.z%MYCPBZ==0) {
    	_dpd_forces_new5<<<dim3(c.ncells.x/MYCPBX, c.ncells.y/MYCPBY, c.ncells.z/MYCPBZ), dim3(32, MYWPB), 0, stream>>>();
		#ifdef TRANSPOSED_ATOMICS
        transpose_acc<<<64,512,0,stream>>>(np);
		#endif
    }
    else {
    	fprintf(stderr,"Incompatible grid config\n");
    }

#ifdef ONESTEP
    check_acc<<<1,1>>>(np);
    CUDA_CHECK( cudaDeviceSynchronize() );
    CUDA_CHECK( cudaDeviceReset() );
    exit(0);
#endif

#ifdef _TIME_PROFILE_
    if (cetriolo % 500 == 0)
    {
	CUDA_CHECK(cudaEventRecord(evstop));
	CUDA_CHECK(cudaEventSynchronize(evstop));
	
	float tms;
	CUDA_CHECK(cudaEventElapsedTime(&tms, evstart, evstop));
	printf("elapsed time for DPD-BULK kernel: %.2f ms\n", tms);
    }
#endif

    CUDA_CHECK(cudaPeekAtLastError());	
}
