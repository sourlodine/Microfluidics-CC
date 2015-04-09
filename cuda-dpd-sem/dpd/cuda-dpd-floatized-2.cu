/*
 *  cuda-dpd.cu
 *  Part of CTC/cuda-dpd-sem/dpd/
 *
 *  Evaluation of DPD force WITHOUT using Newton's 3rd law
 *  Created and authored by Yu-Hang Tang on 2015-03-18.
 *  Copyright 2015. All rights reserved.
 *
 *  Users are NOT authorized
 *  to employ the present software for their own publications
 *  before getting a written permission from the author of this file.
 */

#include <cstdio>
#include <cassert>

#include "../tiny-float.h"
#include "../dpd-rng.h"
#include "../hacks.h"

#define USE_TEXOBJ 0

struct InfoDPD {
    int3 ncells;
    float ncell_x, ncell_y;
    float3 domainsize, invdomainsize, domainstart;
    float invrc, aij, gamma, sigmaf;
    float * axayaz;
    float seed;
	#if (USE_TEXOBJ&1)
    cudaTextureObject_t txoParticles2;
    cudaTextureObject_t txoStart, txoCount;
	#endif
};

__constant__ InfoDPD info;

#if !(USE_TEXOBJ&2)
texture<float4, cudaTextureType1D> texParticles2;
texture<uint, cudaTextureType1D> texStart, texCount;
#endif
#if (USE_TEXOBJ&1)
template<typename TYPE> struct texture_object {
	cudaTextureObject_t txo;
	cudaResourceDesc res_desc;
	cudaTextureDesc tex_desc;
	TYPE *ptr_;
	long long n_;

	texture_object() : txo(0), ptr_(NULL), n_(0LL) {}

	inline operator cudaTextureObject_t () { return txo; };

	inline cudaTextureObject_t rebind( TYPE *ptr, const long long n ) {
		if ( ptr != ptr_ || ( ptr == ptr_ && n > n_ ) ) {
			if ( txo ) CUDA_CHECK( cudaDestroyTextureObject( txo ) );
			ptr_ = ptr;
			n_ = n;
			res_desc.resType = cudaResourceTypeLinear;
			res_desc.res.linear.desc = cudaCreateChannelDesc<TYPE>();
			res_desc.res.linear.devPtr = ptr_;
			res_desc.res.linear.sizeInBytes = sizeof( TYPE ) * n_;
			tex_desc.readMode = cudaReadModeElementType;
			CUDA_CHECK( cudaCreateTextureObject( &txo, &res_desc, &tex_desc, NULL ) );
		}
		return txo;
	}
};

texture_object<float2> txoParticles2;
texture_object<uint> txoStart, txoCount;
#endif

#define _XCPB_ 2
#define _YCPB_ 2
#define _ZCPB_ 1
#define CPB (_XCPB_ * _YCPB_ * _ZCPB_)
//#define  _TIME_PROFILE_

#define LETS_MAKE_IT_MESSY

template<int s>
__device__ float viscosity_function( float x )
{
    return sqrtf( viscosity_function < s - 1 > ( x ) );
}

template<> __device__ float viscosity_function<0>( float x )
{
    return x;
}

// 31+56 FLOPS
__device__ float3 _dpd_interaction( const uint dpid, const float4 xdest, const float4 udest, const uint spid )
{
    const int sentry = xscale( spid, 2.f ); // 1 FLOP
	#if (USE_TEXOBJ&2)
    const float2 stmp0 = tex1Dfetch<float2>( info.txoParticles2, sentry           );
    const float2 stmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 1 ) );
    const float2 stmp2 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 2 ) );
	#else
    const float4 xtmp = tex1Dfetch( texParticles2, sentry           );
    const float4 utmp = tex1Dfetch( texParticles2, xadd( sentry, 1 ) ); // 1 FLOP
    #endif

    const float _xr = xdest.x - xtmp.x; // 1 FLOP
    const float _yr = xdest.y - xtmp.y; // 1 FLOP
    const float _zr = xdest.z - xtmp.z; // 1 FLOP

    const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr; // 5 FLOPS
    assert( rij2 < 1.f );

    const float invrij = rsqrtf( rij2 ); // 1 FLOP
    const float rij = rij2 * invrij; // 1 FLOP
    const float wc = 1.f - rij; // 1 FLOP
    const float wr = viscosity_function < -VISCOSITY_S_LEVEL > ( wc ); // 0 FLOP

    const float xr = _xr * invrij; // 1 FLOP
    const float yr = _yr * invrij; // 1 FLOP
    const float zr = _zr * invrij; // 1 FLOP

    const float rdotv =
        xr * ( udest.x - utmp.x ) +
        yr * ( udest.y - utmp.y ) +
        zr * ( udest.z - utmp.z );  // 8 FLOPS

    const float myrandnr = Logistic::mean0var1( info.seed, xmin(spid,dpid), xmax(spid,dpid) );  // 54+2 FLOP

    const float strength = info.aij * wc - ( info.gamma * wr * rdotv + info.sigmaf * myrandnr ) * wr; // 7 FLOPS

    return make_float3( strength * xr, strength * yr, strength * zr );
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

template<uint COLS, uint ROWS, uint NSRCMAX>
__device__ void core( const uint nsrc, const uint2 * const starts_and_scans,
                      const uint ndst, const uint dststart )
{
	uint srccount = 0;
    assert( ndst == ROWS );

    const uint tid = threadIdx.x;
    const uint wid = threadIdx.y;
    const uint slot = tid / COLS;
    const uint subtid = tid % COLS;

    const uint dpid = xadd( dststart, slot ); // 1 FLOP
    const int entry = xscale( dpid, 2.f ); // 1 FLOP
	#if (USE_TEXOBJ&2)
    const float2 dtmp0 = tex1Dfetch<float2>( info.txoParticles2,       entry      );
    const float2 dtmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 1 ) );
    const float2 dtmp2 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 2 ) );
    const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
    const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );
	#else
    const float4 xdest = tex1Dfetch( texParticles2,       entry      );
    const float4 udest = tex1Dfetch( texParticles2, xadd( entry, 1 ) ); // 1 FLOP
	#endif

    float xforce = 0, yforce = 0, zforce = 0;

    for(uint s = 0; s < nsrc; s = xadd( s, COLS ) )
	{
    	const uint pid  = xadd( s, subtid ); // 1 FLOP
#ifdef LETS_MAKE_IT_MESSY
		uint spid;
		asm( "{ .reg .pred p, q;"
			 "  .reg .f32  key;"
			 "  .reg .f32  scan3, scan6, scan9, scan18;"
			 "  .reg .f32  mystart, myscan;"
			 "  .reg .s32  array;"
			 "  .reg .f32  array_f;"
			 "   mov.b32           array_f, %4;"
			 "   mul.f32           array_f, array_f, 256.0;"
			 "   mov.b32           array, array_f;"
			 "   ld.shared.f32     scan9,  [array +  9*8 + 4];"
			 "   ld.shared.f32     scan18, [array + 18*8 + 4];"
			 "   setp.ge.f32       p, %1, scan9;"
			 "   setp.ge.f32       q, %1, scan18;"
			 "   selp.f32          key, %2, 0.0, p;"
			 "@q add.f32           key, key, %2;"
			 "   mov.b32           array_f, array;"
			 "   fma.f32.rm        array_f, key, 8.0, array_f;"
			 "   mov.b32 array,    array_f;"
			 "   ld.shared.f32     scan3, [array + 3*8 + 4];"
			 "   ld.shared.f32     scan6, [array + 6*8 + 4];"
			 "   setp.ge.f32       p, %1, scan3;"
			 "   setp.ge.f32       q, %1, scan6;"
			 "@p add.f32           key, key, %3;"
			 "@q add.f32           key, key, %3;"
			 "   mov.b32           array_f, %4;"
			 "   mul.f32           array_f, array_f, 256.0;"
			 "   fma.f32.rm        array_f, key, 8.0, array_f;"
			 "   mov.b32           array, array_f;"
			 "   ld.shared.v2.f32 {mystart, myscan}, [array];"
			 "   add.f32           mystart, mystart, %1;"
			 "   sub.f32           mystart, mystart, myscan;"
	         "   mov.b32           %0, mystart;"
	         "}" : "=r"(spid) : "f"(u2f(pid)), "f"(u2f(9u)), "f"(u2f(3u)), "f"(u2f(wid)) );
		// 15 FLOPS
#else
		const uint key9 = xadd( xsel_ge( pid, scan[ 9u            ].y, 9u, 0u ), xsel_ge( pid, scan[ 18u           ].y, 9u, 0u ) );
		const uint key3 = xadd( xsel_ge( pid, scan[ xadd(key9,3u) ].y, 3u, 0u ), xsel_ge( pid, scan[ xadd(key9,6u) ].y, 3u, 0u ) );
		const uint key  = xadd( key9, key3 );
		const uint spid = xsub( xadd( pid, starts_and_scans[key].x ), starts_and_scans[key].y );
#endif


		#if (USE_TEXOBJ&2)
		const int sentry = xscale( spid, 3.f );
		const float2 stmp0 = tex1Dfetch<float2>( info.txoParticles2,       sentry      );
		const float2 stmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 1 ) );
		#else
		const int sentry = xscale( spid, 2.f ); // 1 FLOP
		const float4 xtmp = tex1Dfetch( texParticles2, sentry );
		#endif

		const float xdiff = xdest.x - xtmp.x; // 1 FLOP
		const float ydiff = xdest.y - xtmp.y; // 1 FLOP
		const float zdiff = xdest.z - xtmp.z; // 1 FLOP
#ifdef LETS_MAKE_IT_MESSY
		asm("{ .reg .pred p;"
			"  .reg .f32 srccount_f;"
			"   mov.b32 srccount_f, %0;"
			"   setp.lt.f32 p, %1, %2;"
			"   setp.lt.and.f32 p, %3, 1.0, p;"
			"   setp.ne.and.f32 p, %4, %5, p;"
			"   @p st.shared.u32 [%6], %8;"
			"   @p add.f32 srccount_f, srccount_f, %7;"
			"   mov.b32 %0, srccount_f;"
			"}" : "+r"(srccount) :
			"f"( u2f(pid) ), "f"(u2f(nsrc)), "f"(xdiff * xdiff + ydiff * ydiff + zdiff * zdiff), "f"(u2f(dpid)), "f"(u2f(spid)),
			"r"( xmad(tid,4.f,xmad(wid,128.f,xmad(srccount,512.f,1024u))) ), "f"(u2f(1u)), "r"(spid) : "memory" );
		// 3+(?1)+11
#else
		// 14 FLOPS
		const float interacting = xfcmp_lt(pid, nsrc )
				                * xfcmp_lt( xdiff * xdiff + ydiff * ydiff + zdiff * zdiff, 1.f )
				                * xfcmp_ne( dpid, spid ) ;
		if (interacting) {
			srcids[srccount] = spid;
			srccount = xadd( srccount, 1u ); // 1 FLOP
		}
#endif
		if ( srccount == NSRCMAX ) {
			srccount = xsub( srccount, 1u ); // 1 FLOP
			const float4 utmp = tex1Dfetch( texParticles2, xmad( spid, 2.f, 1u ) );
			const float3 f = _dpd_interaction( dpid, xdest, udest, xtmp, utmp, spid ); // 87 FLOPS

			xforce += f.x; // 1 FLOP
			yforce += f.y; // 1 FLOP
			zforce += f.z; // 1 FLOP
		}
		// 1 FLOP for s++
	}

#pragma unroll 4
	for( uint i = 0; i < srccount; i = xadd( i, 1u ) ) {
#ifdef LETS_MAKE_IT_MESSY
		uint spid;
		asm("ld.shared.u32 %0, [%1];" : "=r"(spid) : "r"( xmad(tid,4.f,xmad(wid,128.f,xmad(i,512.f,1024u))) ) ); // 6 FLOPS
		const float3 f = _dpd_interaction( dpid, xdest, udest, spid ); // 87 FLOPS
#else
		const float3 f = _dpd_interaction( dpid, xdest, udest, srcids[i] ); // 87 FLOPS
#endif
        xforce += f.x; // 1 FLOP
        yforce += f.y; // 1 FLOP
        zforce += f.z; // 1 FLOP

        // 1 FLOP for i++
    }

    for( uint L = COLS / 2; L > 0; L >>= 1 ) {
        xforce += __shfl_xor( xforce, L ); // 1 FLOP
        yforce += __shfl_xor( yforce, L ); // 1 FLOP
        zforce += __shfl_xor( zforce, L ); // 1 FLOP
    }

#ifdef LETS_MAKE_IT_MESSY
    float fcontrib;
    asm("{   .reg .pred isy, isz;"
    	"     setp.f32.eq isy, %1, %5;"
    	"     setp.f32.eq isz, %1, %6;"
    	"     selp.f32 %0, %2, %3, !isy;"
    	"@isz mov.b32 %0, %4;"
    	"}" : "=f"(fcontrib) : "f"(u2f(subtid)), "f"(xforce), "f"(yforce), "f"(zforce), "f"(u2f(1u)), "f"(u2f(2u)) );
    // 2 FLOPS
#else
    //const float fcontrib = xsel_eq( subtid, 0u, xforce, xsel_eq( subtid, 1u, yforce, zforce ) ); // 2 FLOPS
#endif

    if( subtid < 3.f )
        info.axayaz[ xmad( dpid, 3.f, subtid ) ] = fcontrib;  // 2 FLOPS
}

template<uint COLS, uint ROWS, uint NSRCMAX>
__device__ void core_ilp( const uint nsrc, const uint2 * const starts_and_scans,
                          const uint ndst, const uint dststart )
{
    const uint tid    = threadIdx.x;
    const uint wid    = threadIdx.y;
    const uint slot   = tid / COLS;
    const uint subtid = tid % COLS;

    const uint dpid = xadd( dststart, slot ); // 1 FLOP
    const int entry = xscale( dpid, 2.f ); // 1 FLOP
	#if (USE_TEXOBJ&2)
	const float2 dtmp0 = tex1Dfetch<float2>( info.txoParticles2,       entry      );
	const float2 dtmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 1 ) );
	const float2 dtmp2 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 2 ) );
    const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
    const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );
	#else
	const float4 xdest = tex1Dfetch( texParticles2,       entry      );
	const float4 udest = tex1Dfetch( texParticles2, xadd( entry, 1 ) ); // 1 FLOP
	#endif

    float xforce = 0, yforce = 0, zforce = 0;

    for( uint s = 0; s < nsrc; s = xadd( s, NSRCMAX * COLS ) ) {
        uint spids[NSRCMAX];
		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
            const uint pid  = xadd( s, xmad( i, float(COLS), subtid ) );
#ifdef LETS_MAKE_IT_MESSY
    		uint spid;
    		asm( "{ .reg .pred p, q;"
    			 "  .reg .f32  key;"
    			 "  .reg .f32  scan3, scan6, scan9, scan18;"
    			 "  .reg .f32  mystart, myscan;"
    			 "  .reg .s32  array;"
    			 "  .reg .f32  array_f;"
    			 "   mov.b32           array_f, %4;"
    			 "   mul.f32           array_f, array_f, 256.0;"
    			 "   mov.b32           array, array_f;"
    			 "   ld.shared.f32     scan9,  [array +  9*8 + 4];"
    			 "   ld.shared.f32     scan18, [array + 18*8 + 4];"
    			 "   setp.ge.f32       p, %1, scan9;"
    			 "   setp.ge.f32       q, %1, scan18;"
    			 "   selp.f32          key, %2, 0.0, p;"
    			 "@q add.f32           key, key, %2;"
    			 "   mov.b32           array_f, array;"
    			 "   fma.f32.rm        array_f, key, 8.0, array_f;"
    			 "   mov.b32 array,    array_f;"
    			 "   ld.shared.f32     scan3, [array + 3*8 + 4];"
    			 "   ld.shared.f32     scan6, [array + 6*8 + 4];"
    			 "   setp.ge.f32       p, %1, scan3;"
    			 "   setp.ge.f32       q, %1, scan6;"
    			 "@p add.f32           key, key, %3;"
    			 "@q add.f32           key, key, %3;"
    			 "   mov.b32           array_f, %4;"
    			 "   mul.f32           array_f, array_f, 256.0;"
    			 "   fma.f32.rm        array_f, key, 8.0, array_f;"
    			 "   mov.b32           array, array_f;"
    			 "   ld.shared.v2.f32 {mystart, myscan}, [array];"
    			 "   add.f32           mystart, mystart, %1;"
    			 "   sub.f32           mystart, mystart, myscan;"
    	         "   mov.b32           %0, mystart;"
    	         "}" : "=r"(spid) : "f"(u2f(pid)), "f"(u2f(9u)), "f"(u2f(3u)), "f"(u2f(wid)) );
    		// 15 FLOPS
            spids[i] = spid;
#else
    		const uint key9 = xadd( xsel_ge( pid, scan[ 9             ], 9u, 0u ), xsel_ge( pid, scan[ 18            ], 9u, 0u ) );
    		const uint key3 = xadd( xsel_ge( pid, scan[ xadd(key9,3u) ], 3u, 0u ), xsel_ge( pid, scan[ xadd(key9,6u) ], 3u, 0u ) );
    		const uint key  = xadd( key9, key3 );
            spids[i] = xsub( xadd( pid, starts_and_scans[key].x ), starts_and_scans[key].y );
#endif
        }

        uint interacting[NSRCMAX];
		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
			#if (USE_TEXOBJ&2)
			const float2 stmp0 = tex1Dfetch<float2>( info.txoParticles2,       sentry      );
			const float2 stmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 1 ) );
			#else
            const int sentry = xscale( spids[i], 2.f ); // 1 FLOP
			const float4 xtmp = tex1Dfetch( texParticles2,       sentry      );
			#endif

            const float xdiff = xdest.x - xtmp.x; // 1 FLOP
            const float ydiff = xdest.y - xtmp.y; // 1 FLOP
            const float zdiff = xdest.z - xtmp.z; // 1 FLOP
#ifdef LETS_MAKE_IT_MESSY
			uint interacting_one;
            asm("{ .reg .pred p;"
				"   setp.lt.f32 p, %1, %2;"
				"   setp.lt.and.f32 p, %3, 1.0, p;"
				"   set.ne.and.u32.f32 %0, %4, %5, p;"
				"   }" : "=r"(interacting_one)  : "f"(u2f(xadd( s, xmad( i, float(COLS), subtid ) ))), "f"(u2f(nsrc)), "f"(xdiff * xdiff + ydiff * ydiff + zdiff * zdiff), "f"(u2f(dpid)), "f"(u2f(spids[i])) );
            // 12 FLOPS
            interacting[i] = interacting_one;
#else
            interacting[i] = xfcmp_lt( xadd( s, xmad( i, float(COLS), subtid ) ), nsrc )
            		       * xfcmp_lt( xdiff * xdiff + ydiff * ydiff + zdiff * zdiff, 1.f )
            		       * xfcmp_ne( dpid, spids[i] );
#endif
        }

		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
            if( interacting[i] ) {
                const float3 f = _dpd_interaction( dpid, xdest, udest, spids[i] ); // 88 FLOPS

                xforce += f.x; // 1 FLOP
                yforce += f.y; // 1 FLOP
                zforce += f.z; // 1 FLOP
            }
        }

        // 1 FLOP for s += NSRCMAX * COLS;
    }

    for( uint L = COLS / 2; L > 0; L >>= 1 ) {
        xforce += __shfl_xor( xforce, L ); // 1 FLOP
        yforce += __shfl_xor( yforce, L ); // 1 FLOP
        zforce += __shfl_xor( zforce, L ); // 1 FLOP
    }

#ifdef LETS_MAKE_IT_MESSY
    float fcontrib;
    asm("{   .reg .pred isy, isz;"
    	"     setp.f32.eq isy, %1, %5;"
    	"     setp.f32.eq isz, %1, %6;"
    	"     selp.f32 %0, %2, %3, !isy;"
    	"@isz mov.b32 %0, %4;"
    	"}" : "=f"(fcontrib) : "f"(u2f(subtid)), "f"(xforce), "f"(yforce), "f"(zforce), "f"(u2f(1u)), "f"(u2f(2u)) );
    // 2 FLOPS
#else
    const float fcontrib = xsel_eq( subtid, 0u, xforce, xsel_eq( subtid, 1u, yforce, zforce ) );  // 2 FLOPS
#endif

    if( subtid < 3u )
        info.axayaz[ xmad( dpid, 3.f, subtid ) ] = fcontrib;  // 2 FLOPS
}

__global__ __launch_bounds__( 32 * CPB, 16 )
void _dpd_forces_floatized()
{
    assert( blockDim.x == warpSize && blockDim.y == CPB && blockDim.z == 1 );

    const uint tid = threadIdx.x;
    const uint wid = threadIdx.y;

    __shared__ volatile uint2 starts_and_scans[CPB*3][32];

    uint mycount = 0, myscan = 0;
    const int dx = ( tid ) % 3;
    const int dy = ( ( tid / 3 ) ) % 3;
    const int dz = ( ( tid / 9 ) ) % 3;

    if( tid < 27 ) {

        int xcid = blockIdx.x * _XCPB_ + ( ( threadIdx.y ) % _XCPB_ ) + dx - 1;
        int ycid = blockIdx.y * _YCPB_ + ( ( threadIdx.y / _XCPB_ ) % _YCPB_ ) + dy - 1;
        int zcid = blockIdx.z * _ZCPB_ + ( ( threadIdx.y / ( _XCPB_ * _YCPB_ ) ) % _ZCPB_ ) + dz - 1;

        const bool valid_cid =
                ( xcid >= 0 ) && ( xcid < info.ncells.x ) &&
                ( ycid >= 0 ) && ( ycid < info.ncells.y ) &&
                ( zcid >= 0 ) && ( zcid < info.ncells.z );

        xcid = xmin( xsub( info.ncells.x, 1 ), max( 0, xcid ) ); // 2 FLOPS
        ycid = xmin( xsub( info.ncells.y, 1 ), max( 0, ycid ) ); // 2 FLOPS
        zcid = xmin( xsub( info.ncells.z, 1 ), max( 0, zcid ) ); // 2 FLOPS

        const int cid = max( 0, ( zcid * info.ncells.y + ycid ) * info.ncells.x + xcid );
		#if (USE_TEXOBJ&2)
        starts_and_scans[wid][tid].x = tex1Dfetch<uint>( info.txoStart, cid );
        myscan = mycount = valid_cid ? tex1Dfetch<uint>( info.txoCount, cid ) : 0u;
		#else
        starts_and_scans[wid][tid].x = tex1Dfetch( texStart, cid );
        myscan = mycount = valid_cid ? tex1Dfetch( texCount, cid ) : 0u;
		#endif
    }

	#pragma unroll
    for( int L = 1; L < 32; L <<= 1 ) {
    	uint theirscan = __shfl_up( myscan, L );
    	myscan = xadd( myscan, xsel_ge( tid, i2u(L), theirscan, 0u ) ); // 2 FLOPS
    }

    if( tid < 28 )
    	starts_and_scans[wid][tid].y = xsub( myscan, mycount ); // 1 FLOP

    const uint nsrc = starts_and_scans[wid][27].y;
    const uint dststart = starts_and_scans[wid][1 + 3 + 9].x;
    const uint ndst = xsub( starts_and_scans[wid][1 + 3 + 9 + 1].y, starts_and_scans[wid][1 + 3 + 9].y ); // 1 FLOP
    const uint ndst4 = ( ndst >> 2 ) << 2;

    for( uint d = 0; d < ndst4; d = xadd( d, 4u ) ) // 1 FLOP
        core<8, 4, 4>( nsrc, ( const uint2 * )starts_and_scans[wid], 4, xadd( dststart, d ) ); // 1 FLOP

    uint d = ndst4;
    if( xadd( d, 2u ) <= ndst ) { // 1 FLOPS
        core<16, 2, 4>( nsrc, ( const uint2 * )starts_and_scans[wid], 2, xadd( dststart, d ) ); // 1 FLOP
        d = xadd( d, 2u ); // 1 FLOP
    }

    if( d < ndst )
        core_ilp<32, 1, 2>( nsrc, ( const uint2 * )starts_and_scans[wid], 1, xadd( dststart, d ) ); // 1 FLOP
}

__global__ void copy( float *v4, const float *v3, const int n ) {
	for(int i=blockIdx.x*blockDim.x+threadIdx.x;i<n;i+=blockDim.x*gridDim.x) {
			v4[i*8+0] = v3[i*6+0];
			v4[i*8+1] = v3[i*6+1];
			v4[i*8+2] = v3[i*6+2];
			v4[i*8+4] = v3[i*6+3];
			v4[i*8+5] = v3[i*6+4];
			v4[i*8+6] = v3[i*6+5];
	}
}


#ifdef _COUNT_FLOPS
struct _dpd_interaction_flops_counter {
	const static unsigned long long FLOPS = 31ULL + Logistic::mean0var1_flops_counter::FLOPS;
};

template<uint COLS, uint ROWS, uint NSRCMAX>
__device__ void core_flops_counter( unsigned long long *FLOPS, const uint nsrc, const uint2 * const starts_and_scans,
        const uint ndst, const uint dststart )
{
	uint srccount = 0;
    assert( ndst == ROWS );

    const uint tid = threadIdx.x;
    const uint wid = threadIdx.y;
    const uint slot = tid / COLS;
    const uint subtid = tid % COLS;

    const uint dpid = xadd( dststart, slot ); // 1 FLOP
    const int entry = xscale( dpid, 2.f ); // 1 FLOP
	#if (USE_TEXOBJ&2)
    const float2 dtmp0 = tex1Dfetch<float2>( info.txoParticles2,       entry      );
    const float2 dtmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 1 ) );
    const float2 dtmp2 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 2 ) );
    const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
    const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );
	#else
    const float4 xdest = tex1Dfetch( texParticles2,       entry      );
    const float4 udest = tex1Dfetch( texParticles2, xadd( entry, 1 ) ); // 1 FLOP
	#endif

    atomicAdd( FLOPS, 3ULL );

    float xforce = 0, yforce = 0, zforce = 0;

    for(uint s = 0; s < nsrc; s = xadd( s, COLS ) )
	{
    	const uint pid  = xadd( s, subtid ); // 1 FLOP
#ifdef LETS_MAKE_IT_MESSY
		uint spid;
		asm( "{ .reg .pred p, q;"
			 "  .reg .f32  key;"
			 "  .reg .f32  scan3, scan6, scan9, scan18;"
			 "  .reg .f32  mystart, myscan;"
			 "  .reg .s32  array;"
			 "  .reg .f32  array_f;"
			 "   mov.b32           array_f, %4;"
			 "   mul.f32           array_f, array_f, 256.0;"
			 "   mov.b32           array, array_f;"
			 "   ld.shared.f32     scan9,  [array +  9*8 + 4];"
			 "   ld.shared.f32     scan18, [array + 18*8 + 4];"
			 "   setp.ge.f32       p, %1, scan9;"
			 "   setp.ge.f32       q, %1, scan18;"
			 "   selp.f32          key, %2, 0.0, p;"
			 "@q add.f32           key, key, %2;"
			 "   mov.b32           array_f, array;"
			 "   fma.f32.rm        array_f, key, 8.0, array_f;"
			 "   mov.b32 array,    array_f;"
			 "   ld.shared.f32     scan3, [array + 3*8 + 4];"
			 "   ld.shared.f32     scan6, [array + 6*8 + 4];"
			 "   setp.ge.f32       p, %1, scan3;"
			 "   setp.ge.f32       q, %1, scan6;"
			 "@p add.f32           key, key, %3;"
			 "@q add.f32           key, key, %3;"
			 "   mov.b32           array_f, %4;"
			 "   mul.f32           array_f, array_f, 256.0;"
			 "   fma.f32.rm        array_f, key, 8.0, array_f;"
			 "   mov.b32           array, array_f;"
			 "   ld.shared.v2.f32 {mystart, myscan}, [array];"
			 "   add.f32           mystart, mystart, %1;"
			 "   sub.f32           mystart, mystart, myscan;"
	         "   mov.b32           %0, mystart;"
	         "}" : "=r"(spid) : "f"(u2f(pid)), "f"(u2f(9u)), "f"(u2f(3u)), "f"(u2f(wid)) );
		// 15 FLOPS
#else
		const uint key9 = xadd( xsel_ge( pid, scan[ 9u            ].y, 9u, 0u ), xsel_ge( pid, scan[ 18u           ].y, 9u, 0u ) );
		const uint key3 = xadd( xsel_ge( pid, scan[ xadd(key9,3u) ].y, 3u, 0u ), xsel_ge( pid, scan[ xadd(key9,6u) ].y, 3u, 0u ) );
		const uint key  = xadd( key9, key3 );
		const uint spid = xsub( xadd( pid, starts_and_scans[key].x ), starts_and_scans[key].y );
#endif

		#if (USE_TEXOBJ&2)
		const int sentry = xscale( spid, 3.f );
		const float2 stmp0 = tex1Dfetch<float2>( info.txoParticles2,       sentry      );
		const float2 stmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 1 ) );
		#else
		const int sentry = xscale( spid, 2.f ); // 1 FLOP
		const float4 xtmp = tex1Dfetch( texParticles2, sentry );
		#endif

		const float xdiff = xdest.x - xtmp.x; // 1 FLOP
		const float ydiff = xdest.y - xtmp.y; // 1 FLOP
		const float zdiff = xdest.z - xtmp.z; // 1 FLOP
		atomicAdd( FLOPS, 20ULL );
#if 0
		asm("{ .reg .pred p;"
			"  .reg .f32 srccount_f;"
			"   mov.b32 srccount_f, %0;"
			"   setp.lt.f32 p, %1, %2;"
			"   setp.lt.and.f32 p, %3, 1.0, p;"
			"   setp.ne.and.f32 p, %4, %5, p;"
			"   @p st.shared.u32 [%6], %8;"
			"   @p add.f32 srccount_f, srccount_f, %7;"
			"   mov.b32 %0, srccount_f;"
			"}" : "+r"(srccount) :
			"f"( u2f(pid) ), "f"(u2f(nsrc)), "f"(xdiff * xdiff + ydiff * ydiff + zdiff * zdiff), "f"(u2f(dpid)), "f"(u2f(spid)),
			"r"( xmad(tid,4.f,xmad(wid,128.f,xmad(srccount,512.f,1024u))) ), "f"(u2f(1u)), "r"(spid) : "memory" );
		// 3+(?1)+11
#else
		// 14 FLOPS
		const float interacting = xfcmp_lt(pid, nsrc )
				                * xfcmp_lt( xdiff * xdiff + ydiff * ydiff + zdiff * zdiff, 1.f )
				                * xfcmp_ne( dpid, spid ) ;
		atomicAdd( FLOPS, 14ULL );
		if (interacting) {
//			srcids[srccount] = spid;
			srccount = xadd( srccount, 1u ); // 1 FLOP
			atomicAdd( FLOPS, 1ULL );
		}
#endif
		if ( srccount == NSRCMAX ) {
			srccount = xsub( srccount, 1u ); // 1 FLOP
			// why do we reload spid? it's right there in register
			float3 f;// = _dpd_interaction( dpid, xdest, udest, spid ); // 87 FLOPS

			xforce += f.x; // 1 FLOP
			yforce += f.y; // 1 FLOP
			zforce += f.z; // 1 FLOP
			atomicAdd( FLOPS, 4ULL + _dpd_interaction_flops_counter::FLOPS );
		}
		// 1 FLOP for s++
		atomicAdd( FLOPS, 1ULL );
	}

#pragma unroll 4
	for( uint i = 0; i < srccount; i = xadd( i, 1u ) ) {
#ifdef LETS_MAKE_IT_MESSY
		uint spid;
		asm("ld.shared.u32 %0, [%1];" : "=r"(spid) : "r"( xmad(tid,4.f,xmad(wid,128.f,xmad(i,512.f,1024u))) ) ); // 6 FLOPS
		float3 f;// = _dpd_interaction( dpid, xdest, udest, spid ); // 87 FLOPS
		atomicAdd( FLOPS, 6 + _dpd_interaction_flops_counter::FLOPS );
#else
		const float3 f = _dpd_interaction( dpid, xdest, udest, srcids[i] ); // 87 FLOPS
#endif
        xforce += f.x; // 1 FLOP
        yforce += f.y; // 1 FLOP
        zforce += f.z; // 1 FLOP

        // 1 FLOP for i++
        atomicAdd( FLOPS, 4ULL );
    }

    for( uint L = COLS / 2; L > 0; L >>= 1 ) {
        xforce += __shfl_xor( xforce, L ); // 1 FLOP
        yforce += __shfl_xor( yforce, L ); // 1 FLOP
        zforce += __shfl_xor( zforce, L ); // 1 FLOP
        atomicAdd( FLOPS, 3ULL );
    }

#ifdef LETS_MAKE_IT_MESSY
    float fcontrib;
    asm("{   .reg .pred isy, isz;"
    	"     setp.f32.eq isy, %1, %5;"
    	"     setp.f32.eq isz, %1, %6;"
    	"     selp.f32 %0, %2, %3, !isy;"
    	"@isz mov.b32 %0, %4;"
    	"}" : "=f"(fcontrib) : "f"(u2f(subtid)), "f"(xforce), "f"(yforce), "f"(zforce), "f"(u2f(1u)), "f"(u2f(2u)) );
    // 2 FLOPS
    atomicAdd( FLOPS, 2ULL );
#else
    //const float fcontrib = xsel_eq( subtid, 0u, xforce, xsel_eq( subtid, 1u, yforce, zforce ) ); // 2 FLOPS
#endif

    if( subtid < 3.f ) {
        //info.axayaz[ xmad( dpid, 3.f, subtid ) ] = fcontrib;  // 2 FLOPS
        atomicAdd( FLOPS, 2ULL );
    }
}

template<uint COLS, uint ROWS, uint NSRCMAX>
__device__ void core_ilp_flops_counter( unsigned long long *FLOPS, const uint nsrc, const uint2 * const starts_and_scans,
        const uint ndst, const uint dststart )
{
    const uint tid    = threadIdx.x;
    const uint wid    = threadIdx.y;
    const uint slot   = tid / COLS;
    const uint subtid = tid % COLS;

    const uint dpid = xadd( dststart, slot ); // 1 FLOP
    const int entry = xscale( dpid, 2.f ); // 1 FLOP
	#if (USE_TEXOBJ&2)
	const float2 dtmp0 = tex1Dfetch<float2>( info.txoParticles2,       entry      );
	const float2 dtmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 1 ) );
	const float2 dtmp2 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 2 ) );
    const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
    const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );
	#else
	const float4 xdest = tex1Dfetch( texParticles2,       entry      );
	const float4 udest = tex1Dfetch( texParticles2, xadd( entry, 1 ) ); // 1 FLOP
	#endif

	atomicAdd( FLOPS, 3ULL );

    float xforce = 0, yforce = 0, zforce = 0;

    for( uint s = 0; s < nsrc; s = xadd( s, NSRCMAX * COLS ) ) {
        uint spids[NSRCMAX];
		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
            const uint pid  = xadd( s, xmad( i, float(COLS), subtid ) );
            atomicAdd( FLOPS, 3ULL );
#ifdef LETS_MAKE_IT_MESSY
    		uint spid;
    		asm( "{ .reg .pred p, q;"
    			 "  .reg .f32  key;"
    			 "  .reg .f32  scan3, scan6, scan9, scan18;"
    			 "  .reg .f32  mystart, myscan;"
    			 "  .reg .s32  array;"
    			 "  .reg .f32  array_f;"
    			 "   mov.b32           array_f, %4;"
    			 "   mul.f32           array_f, array_f, 256.0;"
    			 "   mov.b32           array, array_f;"
    			 "   ld.shared.f32     scan9,  [array +  9*8 + 4];"
    			 "   ld.shared.f32     scan18, [array + 18*8 + 4];"
    			 "   setp.ge.f32       p, %1, scan9;"
    			 "   setp.ge.f32       q, %1, scan18;"
    			 "   selp.f32          key, %2, 0.0, p;"
    			 "@q add.f32           key, key, %2;"
    			 "   mov.b32           array_f, array;"
    			 "   fma.f32.rm        array_f, key, 8.0, array_f;"
    			 "   mov.b32 array,    array_f;"
    			 "   ld.shared.f32     scan3, [array + 3*8 + 4];"
    			 "   ld.shared.f32     scan6, [array + 6*8 + 4];"
    			 "   setp.ge.f32       p, %1, scan3;"
    			 "   setp.ge.f32       q, %1, scan6;"
    			 "@p add.f32           key, key, %3;"
    			 "@q add.f32           key, key, %3;"
    			 "   mov.b32           array_f, %4;"
    			 "   mul.f32           array_f, array_f, 256.0;"
    			 "   fma.f32.rm        array_f, key, 8.0, array_f;"
    			 "   mov.b32           array, array_f;"
    			 "   ld.shared.v2.f32 {mystart, myscan}, [array];"
    			 "   add.f32           mystart, mystart, %1;"
    			 "   sub.f32           mystart, mystart, myscan;"
    	         "   mov.b32           %0, mystart;"
    	         "}" : "=r"(spid) : "f"(u2f(pid)), "f"(u2f(9u)), "f"(u2f(3u)), "f"(u2f(wid)) );
    		// 15 FLOPS
            spids[i] = spid;
            atomicAdd( FLOPS, 15ULL );
#else
    		const uint key9 = xadd( xsel_ge( pid, scan[ 9             ], 9u, 0u ), xsel_ge( pid, scan[ 18            ], 9u, 0u ) );
    		const uint key3 = xadd( xsel_ge( pid, scan[ xadd(key9,3u) ], 3u, 0u ), xsel_ge( pid, scan[ xadd(key9,6u) ], 3u, 0u ) );
    		const uint key  = xadd( key9, key3 );
            spids[i] = xsub( xadd( pid, starts_and_scans[key].x ), starts_and_scans[key].y );
#endif
        }

        uint interacting[NSRCMAX];
		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
			#if (USE_TEXOBJ&2)
			const float2 stmp0 = tex1Dfetch<float2>( info.txoParticles2,       sentry      );
			const float2 stmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 1 ) );
			#else
            const int sentry = xscale( spids[i], 2.f ); // 1 FLOP
			const float4 xtmp = tex1Dfetch( texParticles2,       sentry      );
			#endif

            const float xdiff = xdest.x - xtmp.x; // 1 FLOP
            const float ydiff = xdest.y - xtmp.y; // 1 FLOP
            const float zdiff = xdest.z - xtmp.z; // 1 FLOP
            atomicAdd( FLOPS, 4ULL );

#ifdef LETS_MAKE_IT_MESSY
			uint interacting_one;
            asm("{ .reg .pred p;"
				"   setp.lt.f32 p, %1, %2;"
				"   setp.lt.and.f32 p, %3, 1.0, p;"
				"   set.ne.and.u32.f32 %0, %4, %5, p;"
				"   }" : "=r"(interacting_one)  : "f"(u2f(xadd( s, xmad( i, float(COLS), subtid ) ))), "f"(u2f(nsrc)), "f"(xdiff * xdiff + ydiff * ydiff + zdiff * zdiff), "f"(u2f(dpid)), "f"(u2f(spids[i])) );
            // 12 FLOPS
            interacting[i] = interacting_one;
            atomicAdd( FLOPS, 12ULL );
#else
            interacting[i] = xfcmp_lt( xadd( s, xmad( i, float(COLS), subtid ) ), nsrc )
            		       * xfcmp_lt( xdiff * xdiff + ydiff * ydiff + zdiff * zdiff, 1.f )
            		       * xfcmp_ne( dpid, spids[i] );
#endif
        }

		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
            if( interacting[i] ) {
                float3 f;// = _dpd_interaction( dpid, xdest, udest, spids[i] ); // 88 FLOPS

                xforce += f.x; // 1 FLOP
                yforce += f.y; // 1 FLOP
                zforce += f.z; // 1 FLOP
                atomicAdd( FLOPS, 3ULL + _dpd_interaction_flops_counter::FLOPS );
            }
        }

        // 1 FLOP for s += NSRCMAX * COLS;
        atomicAdd( FLOPS, 1ULL );
    }

    for( uint L = COLS / 2; L > 0; L >>= 1 ) {
        xforce += __shfl_xor( xforce, L ); // 1 FLOP
        yforce += __shfl_xor( yforce, L ); // 1 FLOP
        zforce += __shfl_xor( zforce, L ); // 1 FLOP
        atomicAdd( FLOPS, 3ULL );
    }

#ifdef LETS_MAKE_IT_MESSY
    float fcontrib;
    asm("{   .reg .pred isy, isz;"
    	"     setp.f32.eq isy, %1, %5;"
    	"     setp.f32.eq isz, %1, %6;"
    	"     selp.f32 %0, %2, %3, !isy;"
    	"@isz mov.b32 %0, %4;"
    	"}" : "=f"(fcontrib) : "f"(u2f(subtid)), "f"(xforce), "f"(yforce), "f"(zforce), "f"(u2f(1u)), "f"(u2f(2u)) );
    // 2 FLOPS
    atomicAdd( FLOPS, 2ULL );
#else
    const float fcontrib = xsel_eq( subtid, 0u, xforce, xsel_eq( subtid, 1u, yforce, zforce ) );  // 2 FLOPS
#endif

    if( subtid < 3u ) {
        //info.axayaz[ xmad( dpid, 3.f, subtid ) ] = fcontrib;  // 2 FLOPS
    	atomicAdd( FLOPS, 2ULL );
    }
}

__global__ __launch_bounds__( 32 * CPB, 16 )
void _dpd_forces_floatized_flops_counter(unsigned long long *FLOPS)
{
    assert( blockDim.x == warpSize && blockDim.y == CPB && blockDim.z == 1 );

    const uint tid = threadIdx.x;
    const uint wid = threadIdx.y;

    __shared__ volatile uint2 starts_and_scans[CPB*3][32];

    uint mycount = 0, myscan = 0;
    const int dx = ( tid ) % 3;
    const int dy = ( ( tid / 3 ) ) % 3;
    const int dz = ( ( tid / 9 ) ) % 3;

    if( tid < 27 ) {

        int xcid = blockIdx.x * _XCPB_ + ( ( threadIdx.y ) % _XCPB_ ) + dx - 1;
        int ycid = blockIdx.y * _YCPB_ + ( ( threadIdx.y / _XCPB_ ) % _YCPB_ ) + dy - 1;
        int zcid = blockIdx.z * _ZCPB_ + ( ( threadIdx.y / ( _XCPB_ * _YCPB_ ) ) % _ZCPB_ ) + dz - 1;

        const bool valid_cid =
                ( xcid >= 0 ) && ( xcid < info.ncells.x ) &&
                ( ycid >= 0 ) && ( ycid < info.ncells.y ) &&
                ( zcid >= 0 ) && ( zcid < info.ncells.z );

        xcid = xmin( xsub( info.ncells.x, 1 ), max( 0, xcid ) ); // 2 FLOPS
        ycid = xmin( xsub( info.ncells.y, 1 ), max( 0, ycid ) ); // 2 FLOPS
        zcid = xmin( xsub( info.ncells.z, 1 ), max( 0, zcid ) ); // 2 FLOPS
        atomicAdd( FLOPS, 6ULL );

        const int cid = max( 0, ( zcid * info.ncells.y + ycid ) * info.ncells.x + xcid );
		#if (USE_TEXOBJ&2)
        starts_and_scans[wid][tid].x = tex1Dfetch<uint>( info.txoStart, cid );
        myscan = mycount = valid_cid ? tex1Dfetch<uint>( info.txoCount, cid ) : 0u;
		#else
        starts_and_scans[wid][tid].x = tex1Dfetch( texStart, cid );
        myscan = mycount = valid_cid ? tex1Dfetch( texCount, cid ) : 0u;
		#endif
    }

	#pragma unroll
    for( int L = 1; L < 32; L <<= 1 ) {
    	uint theirscan = __shfl_up( myscan, L );
    	myscan = xadd( myscan, xsel_ge( tid, i2u(L), theirscan, 0u ) ); // 2 FLOPS
    	atomicAdd( FLOPS, 2ULL );
    }

    if( tid < 28 ) {
    	starts_and_scans[wid][tid].y = xsub( myscan, mycount ); // 1 FLOP
    	atomicAdd( FLOPS, 1ULL );
    }

    const uint nsrc = starts_and_scans[wid][27].y;
    const uint dststart = starts_and_scans[wid][1 + 3 + 9].x;
    const uint ndst = xsub( starts_and_scans[wid][1 + 3 + 9 + 1].y, starts_and_scans[wid][1 + 3 + 9].y ); // 1 FLOP
    const uint ndst4 = ( ndst >> 2 ) << 2;
    atomicAdd( FLOPS, 1ULL );

    for( uint d = 0; d < ndst4; d = xadd( d, 4u ) ) { // 1 FLOP
        core_flops_counter<8, 4, 4>( FLOPS, nsrc, ( const uint2 * )starts_and_scans[wid], 4, xadd( dststart, d ) ); // 1 FLOP
        atomicAdd( FLOPS, 2ULL );
    }

    uint d = ndst4;
    if( xadd( d, 2u ) <= ndst ) { // 1 FLOPS
        core_flops_counter<16, 2, 4>( FLOPS, nsrc, ( const uint2 * )starts_and_scans[wid], 2, xadd( dststart, d ) ); // 1 FLOP
        d = xadd( d, 2u ); // 1 FLOP
        atomicAdd( FLOPS, 3ULL );
    }

    if( d < ndst ) {
        core_ilp_flops_counter<32, 1, 2>( FLOPS, nsrc, ( const uint2 * )starts_and_scans[wid], 1, xadd( dststart, d ) ); // 1 FLOP
        atomicAdd( FLOPS, 1ULL );
    }
}

__global__ void reset_flops( unsigned long long *FLOPS ) {
	*FLOPS = 0ULL;
}

__global__ void print_flops( unsigned long long *FLOPS ) {
	printf("FLOPS count: %llu\n", *FLOPS);
}
#endif

bool fdpd_init = false;

#include "../hacks.h"
#ifdef _TIME_PROFILE_
static cudaEvent_t evstart, evstop;
#endif

void forces_dpd_cuda_nohost( const float * const xyzuvw, float * const axayaz,  const int np,
                             const int * const cellsstart, const int * const cellscount,
                             const float rc,
                             const float XL, const float YL, const float ZL,
                             const float aij,
                             const float gamma,
                             const float sigma,
                             const float invsqrtdt,
                             const float seed, cudaStream_t stream )
{
	if( np == 0 ) {
        printf( "WARNING: forces_dpd_cuda_nohost called with np = %d\n", np );
        return;
    }

    int nx = ( int )ceil( XL / rc );
    int ny = ( int )ceil( YL / rc );
    int nz = ( int )ceil( ZL / rc );
    const int ncells = nx * ny * nz;

	#if !(USE_TEXOBJ&2)
    size_t textureoffset;
	static float *xyz_o_uvw_o;
	static int last_size;
	if (!xyz_o_uvw_o || last_size < np ) {
			if (xyz_o_uvw_o) cudaFree(xyz_o_uvw_o);
			cudaMalloc(&xyz_o_uvw_o,sizeof(float)*8*np);
			last_size = np;
	}
    copy<<<64,512,0,stream>>>( xyz_o_uvw_o, xyzuvw, np );
    CUDA_CHECK( cudaBindTexture( &textureoffset, &texParticles2, xyz_o_uvw_o, &texParticles2.channelDesc, sizeof( float ) * 8 * np ) );
    assert( textureoffset == 0 );
    CUDA_CHECK( cudaBindTexture( &textureoffset, &texStart, cellsstart, &texStart.channelDesc, sizeof( uint ) * ncells ) );
    assert( textureoffset == 0 );
    CUDA_CHECK( cudaBindTexture( &textureoffset, &texCount, cellscount, &texCount.channelDesc, sizeof( uint ) * ncells ) );
    assert( textureoffset == 0 );
	#endif

    InfoDPD c;
    c.ncells = make_int3( nx, ny, nz );
    c.ncell_x = nx;
    c.ncell_y = ny;
    c.domainsize = make_float3( XL, YL, ZL );
    c.invdomainsize = make_float3( 1 / XL, 1 / YL, 1 / ZL );
    c.domainstart = make_float3( -XL * 0.5, -YL * 0.5, -ZL * 0.5 );
    c.invrc = 1.f / rc;
    c.aij = aij;
    c.gamma = gamma;
    c.sigmaf = sigma * invsqrtdt;
    c.axayaz = axayaz;
    c.seed = seed;
	#if (USE_TEXOBJ&1)
    c.txoParticles2 = txoParticles2.rebind( (float2*)const_cast<float*>(xyzuvw), 3 * np );
    c.txoStart = txoStart.rebind( (uint*)const_cast<int*>(cellsstart), ncells );
    c.txoCount = txoCount.rebind( (uint*)const_cast<int*>(cellscount), ncells );
	#endif

	if( !fdpd_init ) {
		#if !(USE_TEXOBJ&2)
        texStart.channelDesc = cudaCreateChannelDesc<uint>();
        texStart.filterMode = cudaFilterModePoint;
        texStart.mipmapFilterMode = cudaFilterModePoint;
        texStart.normalized = 0;

        texCount.channelDesc = cudaCreateChannelDesc<uint>();
        texCount.filterMode = cudaFilterModePoint;
        texCount.mipmapFilterMode = cudaFilterModePoint;
        texCount.normalized = 0;

        texParticles2.channelDesc = cudaCreateChannelDesc<float4>();
        texParticles2.filterMode = cudaFilterModePoint;
        texParticles2.mipmapFilterMode = cudaFilterModePoint;
        texParticles2.normalized = 0;
		#endif

	void ( *dpdkernel )() =  _dpd_forces_floatized;

        CUDA_CHECK( cudaFuncSetCacheConfig( *dpdkernel, cudaFuncCachePreferShared ) );

#ifdef _TIME_PROFILE_
        CUDA_CHECK( cudaEventCreate( &evstart ) );
        CUDA_CHECK( cudaEventCreate( &evstop ) );
#endif
        fdpd_init = true;
    }

    CUDA_CHECK( cudaMemcpyToSymbolAsync( info, &c, sizeof( c ), 0, cudaMemcpyHostToDevice, stream ) );

    static int cetriolo = 0;
    cetriolo++;

#ifdef _TIME_PROFILE_
    if( cetriolo % 500 == 0 )
        CUDA_CHECK( cudaEventRecord( evstart ) );
#endif
    _dpd_forces_floatized <<< dim3( c.ncells.x / _XCPB_,
                          c.ncells.y / _YCPB_,
                          c.ncells.z / _ZCPB_ ), dim3( 32, CPB ), 0, stream >>> ();

#ifdef _COUNT_FLOPS
    {
		static int nstep = 0;
		if ( ++nstep > 6950 ) {
			static unsigned long long *FLOPS;
			if (!FLOPS) cudaMalloc( &FLOPS, 128 * sizeof(unsigned long long) );
			reset_flops<<<1,1,0,stream>>>(FLOPS);
			_dpd_forces_floatized_flops_counter <<< dim3( c.ncells.x / _XCPB_,
									  c.ncells.y / _YCPB_,
									  c.ncells.z / _ZCPB_ ), dim3( 32, CPB ), 0, stream >>> ( FLOPS );
			print_flops<<<1,1,0,stream>>>(FLOPS);
			//count FLOPS
			//report data to scree
		}
    }
#endif

    CUDA_CHECK( cudaPeekAtLastError() );
}
