/*
 *  cuda-dpd.cu
 *  Part of CTC/cuda-dpd-sem/dpd/
 *
 *  Created and authored by Diego Rossinelli on 2015-02-26.
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

//#define PROF_TRIGGER
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
texture<float2, cudaTextureType1D> texParticles2;
texture<uint, cudaTextureType1D> texStart, texCount;
#endif

#define _XCPB_ 2
#define _YCPB_ 2
#define _ZCPB_ 1
#define CPB (_XCPB_ * _YCPB_ * _ZCPB_)
//#define  _TIME_PROFILE_
//#define _INSPECT_

#if 1

template<int s>
__device__ float viscosity_function( float x )
{
    return sqrtf( viscosity_function < s - 1 > ( x ) );
}

template<> __device__ float viscosity_function<0>( float x )
{
    return x;
}

__device__ float3 _dpd_interaction( const uint dpid, const float3 xdest, const float3 udest, const uint spid )
{
    const int sentry = xscale( spid, 3.f );
	#if (USE_TEXOBJ&2)
    const float2 stmp0 = tex1Dfetch<float2>( info.txoParticles2, sentry           );
    const float2 stmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 1 ) );
    const float2 stmp2 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 2 ) );
	#else
    const float2 stmp0 = tex1Dfetch( texParticles2, sentry           );
    const float2 stmp1 = tex1Dfetch( texParticles2, xadd( sentry, 1 ) );
    const float2 stmp2 = tex1Dfetch( texParticles2, xadd( sentry, 2 ) );
    #endif

    const float _xr = xdest.x - stmp0.x;
    const float _yr = xdest.y - stmp0.y;
    const float _zr = xdest.z - stmp1.x;

    const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;
    assert( rij2 < 1.f );

    const float invrij = rsqrtf( rij2 );
    const float rij = rij2 * invrij;
    const float wc = 1.f - rij;
    const float wr = viscosity_function < -VISCOSITY_S_LEVEL > ( wc );

    const float xr = _xr * invrij;
    const float yr = _yr * invrij;
    const float zr = _zr * invrij;

    const float rdotv =
        xr * ( udest.x - stmp1.y ) +
        yr * ( udest.y - stmp2.x ) +
        zr * ( udest.z - stmp2.y );

    const float myrandnr = Logistic::mean0var1( info.seed, xmin(spid,dpid), xmax(spid,dpid) );

    const float strength = info.aij * wc - ( info.gamma * wr * rdotv + info.sigmaf * myrandnr ) * wr;

    return make_float3( strength * xr, strength * yr, strength * zr );
}

template<uint COLS, uint ROWS, uint NSRCMAX>
__device__ void core( const uint nsrc, const uint * const scan, const uint * const starts,
                      const uint ndst, const uint dststart )
{
    uint srcids[NSRCMAX];
    for( int i = 0; i < NSRCMAX; ++i )
        srcids[i] = 0;

    uint srccount = 0;
    assert( ndst == ROWS );

    const uint tid = threadIdx.x;
    const uint slot = tid / COLS;
    const uint subtid = tid % COLS;

    const uint dpid = xadd( dststart, slot );
    const int entry = xscale( dpid, 3.f );
	#if (USE_TEXOBJ&2)
    const float2 dtmp0 = tex1Dfetch<float2>( info.txoParticles2,       entry      );
    const float2 dtmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 1 ) );
    const float2 dtmp2 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 2 ) );
	#else
    const float2 dtmp0 = tex1Dfetch( texParticles2,       entry      );
    const float2 dtmp1 = tex1Dfetch( texParticles2, xadd( entry, 1 ) );
    const float2 dtmp2 = tex1Dfetch( texParticles2, xadd( entry, 2 ) );
	#endif
    const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
    const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );

    float xforce = 0, yforce = 0, zforce = 0;

	for(uint s = 0; s < nsrc; s = xadd( s, COLS ) )
	{
		const uint pid  = xadd( s, subtid );
		const uint key9 = xadd( xsel_ge( pid, scan[ 9             ], 9u, 0u ), xsel_ge( pid, scan[ 18            ], 9u, 0u ) );
		const uint key3 = xadd( xsel_ge( pid, scan[ xadd(key9,3u) ], 3u, 0u ), xsel_ge( pid, scan[ xadd(key9,6u) ], 3u, 0u ) );
		const uint key  = xadd( key9, key3 );

		const uint spid = xsub( xadd( pid, starts[key] ), scan[key] );

		const int sentry = xscale( spid, 3.f );
		#if (USE_TEXOBJ&2)
		const float2 stmp0 = tex1Dfetch<float2>( info.txoParticles2,       sentry      );
		const float2 stmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 1 ) );
		#else
		const float2 stmp0 = tex1Dfetch( texParticles2,       sentry      );
		const float2 stmp1 = tex1Dfetch( texParticles2, xadd( sentry, 1 ) );
		#endif

		const float xdiff = xdest.x - stmp0.x;
		const float ydiff = xdest.y - stmp0.y;
		const float zdiff = xdest.z - stmp1.x;
		const float interacting = xfcmp_lt(pid, nsrc )
				                * xfcmp_lt( xdiff * xdiff + ydiff * ydiff + zdiff * zdiff, 1.f )
				                * xfcmp_ne( dpid, spid ) ;
#ifdef PROF_TRIGGER
		__prof_trigger(00);
#endif

		if (interacting) {
			srcids[srccount] = spid;
			srccount = xadd( srccount, 1u );
#ifdef PROF_TRIGGER
			__prof_trigger(01);
#endif
		}

		if( srccount == NSRCMAX ) {
			srccount = xsub( srccount, 1u );
			const float3 f = _dpd_interaction( dpid, xdest, udest, srcids[srccount] );

			xforce += f.x;
			yforce += f.y;
			zforce += f.z;
		}
	}

#pragma unroll 4
    for( uint i = 0; i < srccount; i = xadd( i, 1u ) ) {
        const float3 f = _dpd_interaction( dpid, xdest, udest, srcids[i] );

        xforce += f.x;
        yforce += f.y;
        zforce += f.z;
    }

    for( uint L = COLS / 2; L > 0; L >>= 1 ) {
        xforce += __shfl_xor( xforce, L );
        yforce += __shfl_xor( yforce, L );
        zforce += __shfl_xor( zforce, L );
    }

    const float fcontrib = xsel_eq( subtid, 0u, xforce, xsel_eq( subtid, 1u, yforce, zforce ) );

    if( subtid < 3.f )
        info.axayaz[ xmad( dpid, 3.f, subtid ) ] = fcontrib;
}

template<uint COLS, uint ROWS, uint NSRCMAX>
__device__ void core_ilp( const uint nsrc, const uint * const scan, const uint * const starts,
                          const uint ndst, const uint dststart )
{
    const uint tid    = threadIdx.x;
    const uint slot   = tid / COLS;
    const uint subtid = tid % COLS;

    const uint dpid = xadd( dststart, slot );
    const int entry = xscale( dpid, 3.f );
	#if (USE_TEXOBJ&2)
	const float2 dtmp0 = tex1Dfetch<float2>( info.txoParticles2,       entry      );
	const float2 dtmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 1 ) );
	const float2 dtmp2 = tex1Dfetch<float2>( info.txoParticles2, xadd( entry, 2 ) );
	#else
	const float2 dtmp0 = tex1Dfetch( texParticles2,       entry      );
	const float2 dtmp1 = tex1Dfetch( texParticles2, xadd( entry, 1 ) );
	const float2 dtmp2 = tex1Dfetch( texParticles2, xadd( entry, 2 ) );
	#endif
    const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
    const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );

    float xforce = 0, yforce = 0, zforce = 0;

    for( uint s = 0; s < nsrc; s = xadd( s, NSRCMAX * COLS ) ) {
        uint spids[NSRCMAX];
		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
            const uint pid  = xadd( s, xmad( i, float(COLS), subtid ) );
    		const uint key9 = xadd( xsel_ge( pid, scan[ 9             ], 9u, 0u ), xsel_ge( pid, scan[ 18            ], 9u, 0u ) );
    		const uint key3 = xadd( xsel_ge( pid, scan[ xadd(key9,3u) ], 3u, 0u ), xsel_ge( pid, scan[ xadd(key9,6u) ], 3u, 0u ) );
    		const uint key  = xadd( key9, key3 );

            spids[i] = xsub( xadd( pid, starts[key] ), scan[key] );
        }

        bool interacting[NSRCMAX];
		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
            const int sentry = xscale( spids[i], 3.f );
			#if (USE_TEXOBJ&2)
			const float2 stmp0 = tex1Dfetch<float2>( info.txoParticles2,       sentry      );
			const float2 stmp1 = tex1Dfetch<float2>( info.txoParticles2, xadd( sentry, 1 ) );
			#else
			const float2 stmp0 = tex1Dfetch( texParticles2,       sentry      );
			const float2 stmp1 = tex1Dfetch( texParticles2, xadd( sentry, 1 ) );
			#endif

            const float xdiff = xdest.x - stmp0.x;
            const float ydiff = xdest.y - stmp0.y;
            const float zdiff = xdest.z - stmp1.x;
            interacting[i] = xfcmp_lt( xadd( s, xmad( i, float(COLS), subtid ) ), nsrc )
            		       * xfcmp_lt( xdiff * xdiff + ydiff * ydiff + zdiff * zdiff, 1.f )
            		       * xfcmp_ne( dpid, spids[i] );
        }

		#pragma unroll
        for( uint i = 0; i < NSRCMAX; ++i ) {
            if( interacting[i] ) {
                const float3 f = _dpd_interaction( dpid, xdest, udest, spids[i] );

                xforce += f.x;
                yforce += f.y;
                zforce += f.z;
            }
        }
    }

    for( uint L = COLS / 2; L > 0; L >>= 1 ) {
        xforce += __shfl_xor( xforce, L );
        yforce += __shfl_xor( yforce, L );
        zforce += __shfl_xor( zforce, L );
    }

    const float fcontrib = xsel_eq( subtid, 0u, xforce, xsel_eq( subtid, 1u, yforce, zforce ) );

    if( subtid < 3u )
        info.axayaz[ xmad( dpid, 3.f, subtid ) ] = fcontrib;
}

__global__ __launch_bounds__( 32 * CPB, 16 )
void _dpd_forces()
{
    assert( blockDim.x == warpSize && blockDim.y == CPB && blockDim.z == 1 );

    const uint tid = threadIdx.x;
    const uint wid = threadIdx.y;

    __shared__ volatile uint starts[CPB][32], scan[CPB][32];

    uint mycount = 0, myscan = 0;
    if( tid < 27 ) {
        const int dx = ( tid ) % 3;
        const int dy = ( ( tid / 3 ) ) % 3;
        const int dz = ( ( tid / 9 ) ) % 3;

        int xcid = blockIdx.x * _XCPB_ + ( ( threadIdx.y ) % _XCPB_ ) + dx - 1;
        int ycid = blockIdx.y * _YCPB_ + ( ( threadIdx.y / _XCPB_ ) % _YCPB_ ) + dy - 1;
        int zcid = blockIdx.z * _ZCPB_ + ( ( threadIdx.y / ( _XCPB_ * _YCPB_ ) ) % _ZCPB_ ) + dz - 1;

        const bool valid_cid =
                ( xcid >= 0 ) && ( xcid < info.ncells.x ) &&
                ( ycid >= 0 ) && ( ycid < info.ncells.y ) &&
                ( zcid >= 0 ) && ( zcid < info.ncells.z );

        xcid = xmin( xsub( info.ncells.x, 1 ), max( 0, xcid ) );
        ycid = xmin( xsub( info.ncells.y, 1 ), max( 0, ycid ) );
        zcid = xmin( xsub( info.ncells.z, 1 ), max( 0, zcid ) );

        const int cid = max( 0, ( zcid * info.ncells.y + ycid ) * info.ncells.x + xcid );
		#if (USE_TEXOBJ&2)
        starts[wid][tid] = tex1Dfetch<uint>( info.txoStart, cid );
        myscan = mycount = valid_cid ? tex1Dfetch<uint>( info.txoCount, cid ) : 0u;
		#else
        starts[wid][tid] = tex1Dfetch( texStart, cid );
        myscan = mycount = valid_cid ? tex1Dfetch( texCount, cid ) : 0u;
		#endif
    }

    for( uint L = 1u; L < 32u; L <<= 1 ) {
    	uint theirscan = i2u( __shfl_up( u2i(myscan), u2i(L) ) );
        myscan = xadd( myscan, xsel_ge( tid, L, theirscan, 0u ) );
    }

    if( tid < 28 )
        scan[wid][tid] = xsub( myscan, mycount );

    const uint nsrc = scan[wid][27];
    const uint dststart = starts[wid][1 + 3 + 9];
    const uint ndst = xsub( scan[wid][1 + 3 + 9 + 1], scan[wid][1 + 3 + 9] );
    const uint ndst4 = ( ndst >> 2 ) << 2;

    for( uint d = 0; d < ndst4; d = xadd( d, 4u ) )
        core<8, 4, 4>( nsrc, ( const uint * )scan[wid], ( const uint * )starts[wid], 4, xadd( dststart, d ) );

    uint d = ndst4;
    if( xadd( d, 2u ) <= ndst ) {
        core<16, 2, 4>( nsrc, ( const uint * )scan[wid], ( const uint * )starts[wid], 2, xadd( dststart, d ) );
        d = xadd( d, 2u );
    }

    if( d < ndst )
        core_ilp<32, 1, 2>( nsrc, ( const uint * )scan[wid], ( const uint * )starts[wid], 1, xadd( dststart, d ) );
}

#else
__global__ __launch_bounds__( 32 * CPB, 16 )
void _dpd_forces()
{
    const int COLS = 32;
    const int ROWS = 1;
    assert( warpSize == COLS * ROWS );
    assert( blockDim.x == warpSize && blockDim.y == CPB && blockDim.z == 1 );
    assert( ROWS * 3 <= warpSize );

    const int tid = threadIdx.x;
    const int subtid = tid % COLS;
    const int slot = tid / COLS;
    const int wid = threadIdx.y;

    __shared__ int volatile starts[CPB][32], scan[CPB][32];

    int mycount = 0, myscan = 0;
    if( tid < 27 ) {
        const int dx = ( tid ) % 3;
        const int dy = ( ( tid / 3 ) ) % 3;
        const int dz = ( ( tid / 9 ) ) % 3;

        int xcid = blockIdx.x * _XCPB_ + ( ( threadIdx.y ) % _XCPB_ ) + dx - 1;
        int ycid = blockIdx.y * _YCPB_ + ( ( threadIdx.y / _XCPB_ ) % _YCPB_ ) + dy - 1;
        int zcid = blockIdx.z * _ZCPB_ + ( ( threadIdx.y / ( _XCPB_ * _YCPB_ ) ) % _ZCPB_ ) + dz - 1;

        const bool valid_cid =
            xcid >= 0 && xcid < info.ncells.x &&
            ycid >= 0 && ycid < info.ncells.y &&
            zcid >= 0 && zcid < info.ncells.z ;

        xcid = min( info.ncells.x - 1, max( 0, xcid ) );
        ycid = min( info.ncells.y - 1, max( 0, ycid ) );
        zcid = min( info.ncells.z - 1, max( 0, zcid ) );

        const int cid = max( 0, xcid + info.ncells.x * ( ycid + info.ncells.y * zcid ) );

        starts[wid][tid] = tex1Dfetch( texStart, cid );

        myscan = mycount = valid_cid * tex1Dfetch( texCount, cid );
    }

    for( int L = 1; L < 32; L <<= 1 )
        myscan += ( tid >= L ) * __shfl_up( myscan, L ) ;

    if( tid < 28 )
        scan[wid][tid] = myscan - mycount;

    const int dststart = starts[wid][1 + 3 + 9];
    const int nsrc = scan[wid][27], ndst = scan[wid][1 + 3 + 9 + 1] - scan[wid][1 + 3 + 9];

    for( int d = 0; d < ndst; d += ROWS ) {
        const int np1 = min( ndst - d, ROWS );

        const int dpid = dststart + d + slot;
        const int entry = 3 * dpid;
        float2 dtmp0 = tex1Dfetch( texParticles2, entry );
        float2 dtmp1 = tex1Dfetch( texParticles2, entry + 1 );
        float2 dtmp2 = tex1Dfetch( texParticles2, entry + 2 );

        float xforce = 0, yforce = 0, zforce = 0;

        for( int s = 0; s < nsrc; s += COLS ) {
            const int np2 = min( nsrc - s, COLS );

            const int pid = s + subtid;
            const int key9 = 9 * ( ( pid >= scan[wid][9] ) + ( pid >= scan[wid][18] ) );
            const int key3 = 3 * ( ( pid >= scan[wid][key9 + 3] ) + ( pid >= scan[wid][key9 + 6] ) );
            const int key = key9 + key3;

            const int spid = pid - scan[wid][key] + starts[wid][key];
            const int sentry = 3 * spid;
            const float2 stmp0 = tex1Dfetch( texParticles2, sentry );
            const float2 stmp1 = tex1Dfetch( texParticles2, sentry + 1 );
            const float2 stmp2 = tex1Dfetch( texParticles2, sentry + 2 );

#ifndef NDEBUG
            {
                const int key1 = ( pid >= scan[wid][key9 + key3 + 1] ) + ( pid >= scan[wid][key9 + key3 + 2] );
                const int keyref = key9 + key3 + key1;
                assert( keyref >= 0 && keyref < 27 );
                assert( pid >= scan[wid][keyref] );
                assert( pid < scan[wid][keyref + 1] || pid >= nsrc );

                const int spidref = pid - scan[wid][keyref] + starts[wid][keyref];
                assert( spidref == spid || pid >= nsrc );
            }
#endif

            {
                const float xdiff = dtmp0.x - stmp0.x;
                const float ydiff = dtmp0.y - stmp0.y;
                const float zdiff = dtmp1.x - stmp1.x;

#ifndef _NONPERIODIC_KERNEL_
                asdasda
                const float _xr = xdiff - info.domainsize.x * floorf( 0.5f + xdiff * info.invdomainsize.x );
                const float _yr = ydiff - info.domainsize.y * floorf( 0.5f + ydiff * info.invdomainsize.y );
                const float _zr = zdiff - info.domainsize.z * floorf( 0.5f + zdiff * info.invdomainsize.z );
#else
                const float _xr = xdiff;
                const float _yr = ydiff;
                const float _zr = zdiff;
#endif
                const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;
                const float invrij = rsqrtf( rij2 );
                const float rij = rij2 * invrij;
                const float argwr = max( ( float )0, 1 - rij * info.invrc );
                const float wr = powf( argwr, powf( 0.5f, -VISCOSITY_S_LEVEL ) );

                const float xr = _xr * invrij;
                const float yr = _yr * invrij;
                const float zr = _zr * invrij;

                const float rdotv =
                    xr * ( dtmp1.y - stmp1.y ) +
                    yr * ( dtmp2.x - stmp2.x ) +
                    zr * ( dtmp2.y - stmp2.y );

                const float myrandnr = Logistic::mean0var1( info.seed, min( spid, dpid ), max( spid, dpid ) );

                const float strength = info.aij * argwr - ( info.gamma * wr * rdotv + info.sigmaf * myrandnr ) * wr;
                const bool valid = ( dpid != spid ) && ( slot < np1 ) && ( subtid < np2 );

                if( valid ) {
#ifdef _CHECK_
                    xforce += ( rij2 < 1 );
                    yforce += wr;
                    zforce += 0;
#else
                    xforce += strength * xr;
                    yforce += strength * yr;
                    zforce += strength * zr;
#endif
                }
            }
        }

        for( int L = COLS / 2; L > 0; L >>= 1 ) {
            xforce += __shfl_xor( xforce, L );
            yforce += __shfl_xor( yforce, L );
            zforce += __shfl_xor( zforce, L );
        }

        const int c = ( subtid % 3 );
        const float fcontrib = ( c == 0 ) * xforce + ( c == 1 ) * yforce + ( c == 2 ) * zforce; //f[subtid % 3];
        const int dstpid = dststart + d + slot;

        if( slot < np1 )
            info.axayaz[c + 3 * dstpid] = fcontrib;
    }
}
#endif

#ifdef _INSPECT_
__global__ __launch_bounds__( 32 * CPB, 8 )
void inspect_dpd_forces( const int COLS, const int ROWS, const int nparticles, int2 * const entries, const int nentries )
{
    assert( nentries == COLS * nparticles );
    assert( warpSize == COLS * ROWS );
    assert( blockDim.x == warpSize && blockDim.y == CPB && blockDim.z == 1 );
    assert( ROWS * 3 <= warpSize );

    const int tid = threadIdx.x;
    const int subtid = tid % COLS;
    const int slot = tid / COLS;
    const int wid = threadIdx.y;

    __shared__ int volatile starts[CPB][32], scan[CPB][32];

    int mycount = 0, myscan = 0;
    if( tid < 27 ) {
        const int dx = ( tid ) % 3;
        const int dy = ( ( tid / 3 ) ) % 3;
        const int dz = ( ( tid / 9 ) ) % 3;

        int xcid = blockIdx.x * _XCPB_ + ( ( threadIdx.y ) % _XCPB_ ) + dx - 1;
        int ycid = blockIdx.y * _YCPB_ + ( ( threadIdx.y / _XCPB_ ) % _YCPB_ ) + dy - 1;
        int zcid = blockIdx.z * _ZCPB_ + ( ( threadIdx.y / ( _XCPB_ * _YCPB_ ) ) % _ZCPB_ ) + dz - 1;

        const bool valid_cid =
            xcid >= 0 && xcid < info.ncells.x &&
            ycid >= 0 && ycid < info.ncells.y &&
            zcid >= 0 && zcid < info.ncells.z ;

        xcid = min( info.ncells.x - 1, max( 0, xcid ) );
        ycid = min( info.ncells.y - 1, max( 0, ycid ) );
        zcid = min( info.ncells.z - 1, max( 0, zcid ) );

        const int cid = max( 0, xcid + info.ncells.x * ( ycid + info.ncells.y * zcid ) );

        starts[wid][tid] = tex1Dfetch( texStart, cid );

        myscan = mycount = valid_cid * tex1Dfetch( texCount, cid );
    }

    for( int L = 1; L < 32; L <<= 1 )
        myscan += ( tid >= L ) * __shfl_up( myscan, L ) ;

    if( tid < 28 )
        scan[wid][tid] = myscan - mycount;

    const int dststart = starts[wid][1 + 3 + 9];
    const int nsrc = scan[wid][27], ndst = scan[wid][1 + 3 + 9 + 1] - scan[wid][1 + 3 + 9];

    for( int d = 0; d < ndst; d += ROWS ) {
        //int srccount = 0;

        const int np1 = min( ndst - d, ROWS );

        const int dpid = dststart + d + slot;
        const int entry = 3 * dpid;

        const float2 dtmp0 = tex1Dfetch( texParticles2, entry );
        const float2 dtmp1 = tex1Dfetch( texParticles2, entry + 1 );
        const float2 dtmp2 = tex1Dfetch( texParticles2, entry + 2 );
        const float3 xdest = make_float3( dtmp0.x, dtmp0.y, dtmp1.x );
        const float3 udest = make_float3( dtmp1.y, dtmp2.x, dtmp2.y );

        int ninteractions = 0, npotentialinteractions = 0;

        for( int s = 0; s < nsrc; s += COLS ) {
            const int np2 = min( nsrc - s, COLS );

            const int pid = s + subtid;
            const int key9 = 9 * ( ( pid >= scan[wid][9] ) + ( pid >= scan[wid][18] ) );
            const int key3 = 3 * ( ( pid >= scan[wid][key9 + 3] ) + ( pid >= scan[wid][key9 + 6] ) );
            const int key = key9 + key3;

            const int spid = pid - scan[wid][key] + starts[wid][key];
            const int sentry = 3 * spid;
            const float2 stmp0 = tex1Dfetch( texParticles2, sentry );
            const float2 stmp1 = tex1Dfetch( texParticles2, sentry + 1 );

            const float xdiff = xdest.x - stmp0.x;
            const float ydiff = xdest.y - stmp0.y;
            const float zdiff = xdest.z - stmp1.x;
            const bool interacting = ( dpid != spid ) && ( slot < np1 ) && ( subtid < np2 ) &&
                                     ( xdiff * xdiff + ydiff * ydiff + zdiff * zdiff < 1 );

            ninteractions += ( int )( interacting );
            npotentialinteractions += 1;
        }

        if( slot < np1 )
            entries[subtid + COLS * dpid] = make_int2( ninteractions, npotentialinteractions );
    }
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
    CUDA_CHECK( cudaBindTexture( &textureoffset, &texParticles2, xyzuvw, &texParticles2.channelDesc, sizeof( float ) * 6 * np ) );
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
	{
		static cudaResourceDesc res_desc;
		static cudaTextureDesc tex_desc;
		static cudaTextureObject_t txo;
		if ( const_cast<float*>(xyzuvw) != res_desc.res.linear.devPtr ) {
			if ( txo ) {
				printf("destroyed\n");
				CUDA_CHECK( cudaDestroyTextureObject(txo) );
			}
			res_desc.resType = cudaResourceTypeLinear;
			res_desc.res.linear.devPtr = const_cast<float*>(xyzuvw);
			res_desc.res.linear.desc = cudaCreateChannelDesc<float2>();
			res_desc.res.linear.sizeInBytes = sizeof( float ) * 6 * np;
			tex_desc.readMode = cudaReadModeElementType;
			CUDA_CHECK( cudaCreateTextureObject( &txo, &res_desc, &tex_desc, NULL ) );
			printf("created\n");
		}
		c.txoParticles2 = txo;
	}

	{
		static cudaResourceDesc res_desc;
		static cudaTextureDesc tex_desc;
		static cudaTextureObject_t txo;
		if ( const_cast<int*>(cellsstart) != res_desc.res.linear.devPtr ) {
			if ( txo ) {
				printf("destroyed\n");
				CUDA_CHECK( cudaDestroyTextureObject(txo) );
			}
			res_desc.resType = cudaResourceTypeLinear;
			res_desc.res.linear.devPtr = const_cast<int*>(cellsstart);
			res_desc.res.linear.desc = cudaCreateChannelDesc<uint>();
			res_desc.res.linear.sizeInBytes = sizeof( uint ) * ncells;
			tex_desc.readMode = cudaReadModeElementType;
			CUDA_CHECK( cudaCreateTextureObject( &txo, &res_desc, &tex_desc, NULL ) );
			printf("created\n");
		}
		c.txoStart = txo;
	}

	{
		static cudaResourceDesc res_desc;
		static cudaTextureDesc tex_desc;
		static cudaTextureObject_t txo;
		if ( const_cast<int*>(cellscount) != res_desc.res.linear.devPtr ) {
			if ( txo ) {
				printf("destroyed\n");
				CUDA_CHECK( cudaDestroyTextureObject(txo) );
			}
			res_desc.resType = cudaResourceTypeLinear;
			res_desc.res.linear.devPtr = const_cast<int*>(cellscount);
			res_desc.res.linear.desc = cudaCreateChannelDesc<uint>();
			res_desc.res.linear.sizeInBytes = sizeof( uint ) * ncells;
			tex_desc.readMode = cudaReadModeElementType;
			CUDA_CHECK( cudaCreateTextureObject( &txo, &res_desc, &tex_desc, NULL ) );
			printf("created\n");
		}
		c.txoCount = txo;
	}
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

        texParticles2.channelDesc = cudaCreateChannelDesc<float2>();
        texParticles2.filterMode = cudaFilterModePoint;
        texParticles2.mipmapFilterMode = cudaFilterModePoint;
        texParticles2.normalized = 0;
		#endif

		void ( *dpdkernel )() =  _dpd_forces;

        CUDA_CHECK( cudaFuncSetCacheConfig( *dpdkernel, cudaFuncCachePreferL1 ) );

#ifdef _TIME_PROFILE_
        CUDA_CHECK( cudaEventCreate( &evstart ) );
        CUDA_CHECK( cudaEventCreate( &evstop ) );
#endif
        fdpd_init = true;
    }

    CUDA_CHECK( cudaMemcpyToSymbolAsync( info, &c, sizeof( c ), 0, cudaMemcpyHostToDevice, stream ) );

    static int cetriolo = 0;
    cetriolo++;

#ifdef _INSPECT_
    {
        //inspect irregularity of the computation,
        //report data to file
        if( cetriolo % 1000 == 0 ) {
            enum { COLS = 16, ROWS = 2 };

            const size_t nentries = np * COLS;

            int2 * data;
            CUDA_CHECK( cudaHostAlloc( &data, sizeof( int2 ) * nentries, cudaHostAllocMapped ) );
            memset( data, 0xff, sizeof( int2 ) * nentries );

            int * devptr;
            CUDA_CHECK( cudaHostGetDevicePointer( &devptr, data, 0 ) );

            inspect_dpd_forces <<< dim3( c.ncells.x / _XCPB_, c.ncells.y / _YCPB_, c.ncells.z / _ZCPB_ ), dim3( 32, CPB ), 0, stream >>>
            ( COLS, ROWS, np, data, nentries );

            CUDA_CHECK( cudaDeviceSynchronize() );

            char path2report[2000];
            sprintf( path2report, "inspection-%d-tstep.txt", cetriolo );

            FILE * f = fopen( path2report, "w" );
            assert( f );

            for( int i = 0, c = 0; i < np; ++i ) {
                fprintf( f, "pid %05d: ", i );

                int s = 0, pot = 0;
                for( int j = 0; j < COLS; ++j, ++c ) {
                    fprintf( f, "%02d ", data[c].x );
                    s += data[c].x;
                    pot += data[c].y;
                }

                fprintf( f, " sum: %02d pot: %d\n", s, ( pot + COLS - 1 ) / ( COLS ) );
            }

            fclose( f );

            CUDA_CHECK( cudaFreeHost( data ) );
            printf( "inspection saved to %s.\n", path2report );
        }
    }
#endif

#ifdef _TIME_PROFILE_
    if( cetriolo % 500 == 0 )
        CUDA_CHECK( cudaEventRecord( evstart ) );
#endif
    _dpd_forces <<< dim3( c.ncells.x / _XCPB_,
                          c.ncells.y / _YCPB_,
                          c.ncells.z / _ZCPB_ ), dim3( 32, CPB ), 0, stream >>> ();

#ifdef _TIME_PROFILE_
    if( cetriolo % 500 == 0 ) {
        CUDA_CHECK( cudaEventRecord( evstop ) );
        CUDA_CHECK( cudaEventSynchronize( evstop ) );

        float tms;
        CUDA_CHECK( cudaEventElapsedTime( &tms, evstart, evstop ) );
        printf( "elapsed time for DPD-BULK kernel: %.2f ms\n", tms );
    }
#endif

    CUDA_CHECK( cudaPeekAtLastError() );
}

#include <cmath>
#include <unistd.h>

#include "../cell-lists.h"

int fdpd_oldnp = 0, fdpd_oldnc = 0;

float * fdpd_xyzuvw = NULL, * fdpd_axayaz = NULL;
int * fdpd_start = NULL, * fdpd_count = NULL;

void forces_dpd_cuda_aos( float * const _xyzuvw, float * const _axayaz,
                          int * const order, const int np,
                          const float rc,
                          const float XL, const float YL, const float ZL,
                          const float aij,
                          const float gamma,
                          const float sigma,
                          const float invsqrtdt,
                          const float seed,
                          const bool nohost )
{
    if( np == 0 ) {
        printf( "WARNING: forces_dpd_cuda_aos called with np = %d\n", np );
        return;
    }

    int nx = ( int )ceil( XL / rc );
    int ny = ( int )ceil( YL / rc );
    int nz = ( int )ceil( ZL / rc );
    const int ncells = nx * ny * nz;

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

        texParticles2.channelDesc = cudaCreateChannelDesc<float2>();
        texParticles2.filterMode = cudaFilterModePoint;
        texParticles2.mipmapFilterMode = cudaFilterModePoint;
        texParticles2.normalized = 0;
		#endif

        fdpd_init = true;
    }

    if( fdpd_oldnp < np ) {
        if( fdpd_oldnp > 0 ) {
            CUDA_CHECK( cudaFree( fdpd_xyzuvw ) );
            CUDA_CHECK( cudaFree( fdpd_axayaz ) );
        }

        CUDA_CHECK( cudaMalloc( &fdpd_xyzuvw, sizeof( float ) * 6 * np ) );
        CUDA_CHECK( cudaMalloc( &fdpd_axayaz, sizeof( float ) * 3 * np ) );

		#if !(USE_TEXOBJ&2)
        size_t textureoffset;
        CUDA_CHECK( cudaBindTexture( &textureoffset, &texParticles2, fdpd_xyzuvw, &texParticles2.channelDesc, sizeof( float ) * 6 * np ) );
		#endif

        fdpd_oldnp = np;
    }

    if( fdpd_oldnc < ncells ) {
        if( fdpd_oldnc > 0 ) {
            CUDA_CHECK( cudaFree( fdpd_start ) );
            CUDA_CHECK( cudaFree( fdpd_count ) );
        }

        CUDA_CHECK( cudaMalloc( &fdpd_start, sizeof( uint ) * ncells ) );
        CUDA_CHECK( cudaMalloc( &fdpd_count, sizeof( uint ) * ncells ) );

		#if !(USE_TEXOBJ&2)
        size_t textureoffset = 0;
        CUDA_CHECK( cudaBindTexture( &textureoffset, &texStart, fdpd_start, &texStart.channelDesc, sizeof( uint ) * ncells ) );
        CUDA_CHECK( cudaBindTexture( &textureoffset, &texCount, fdpd_count, &texCount.channelDesc, sizeof( uint ) * ncells ) );
		#endif

        fdpd_oldnc = ncells;
    }

    CUDA_CHECK( cudaMemcpyAsync( fdpd_xyzuvw, _xyzuvw, sizeof( float ) * np * 6, nohost ? cudaMemcpyDeviceToDevice : cudaMemcpyHostToDevice, 0 ) );

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
    c.axayaz = fdpd_axayaz;
    c.seed = seed;

    build_clists( fdpd_xyzuvw, np, rc, c.ncells.x, c.ncells.y, c.ncells.z,
                  c.domainstart.x, c.domainstart.y, c.domainstart.z,
                  order, fdpd_start, fdpd_count, NULL );

    //TextureWrap texStart(_ptr(starts), ncells), texCount(_ptr(counts), ncells);
    //TextureWrap texParticles((float2*)_ptr(xyzuvw), 3 * np);

    CUDA_CHECK( cudaMemcpyToSymbolAsync( info, &c, sizeof( c ), 0 ) );

    _dpd_forces <<< dim3( c.ncells.x / _XCPB_,
                          c.ncells.y / _YCPB_,
                          c.ncells.z / _ZCPB_ ), dim3( 32, CPB ) >>> ();

    CUDA_CHECK( cudaPeekAtLastError() );

//copy xyzuvw as well?!?
    if( nohost ) {
        CUDA_CHECK( cudaMemcpy( _xyzuvw, fdpd_xyzuvw, sizeof( float ) * 6 * np, cudaMemcpyDeviceToDevice ) );
        CUDA_CHECK( cudaMemcpy( _axayaz, fdpd_axayaz, sizeof( float ) * 3 * np, cudaMemcpyDeviceToDevice ) );
    } else
        CUDA_CHECK( cudaMemcpy( _axayaz, fdpd_axayaz, sizeof( float ) * 3 * np, cudaMemcpyDeviceToHost ) );

#ifdef _CHECK_
    CUDA_CHECK( cudaThreadSynchronize() );

    for( int ii = 0; ii < np; ++ii ) {
        printf( "pid %d -> %f %f %f\n", ii, ( float )axayaz[0 + 3 * ii], ( float )axayaz[1 + 3 * ii], ( float )axayaz[2 + 3 * ii] );

        int cnt = 0;
        float fc = 0;
        const int i = order[ii];
        printf( "devi coords are %f %f %f\n", ( float )xyzuvw[0 + 6 * ii], ( float )xyzuvw[1 + 6 * ii], ( float )xyzuvw[2 + 6 * ii] );
        printf( "host coords are %f %f %f\n", ( float )_xyzuvw[0 + 6 * i], ( float )_xyzuvw[1 + 6 * i], ( float )_xyzuvw[2 + 6 * i] );

        for( int j = 0; j < np; ++j ) {
            if( i == j )
                continue;

            float xr = _xyzuvw[0 + 6 * i] - _xyzuvw[0 + 6 * j];
            float yr = _xyzuvw[1 + 6 * i] - _xyzuvw[1 + 6 * j];
            float zr = _xyzuvw[2 + 6 * i] - _xyzuvw[2 + 6 * j];

            xr -= c.domainsize.x *  ::floor( 0.5f + xr / c.domainsize.x );
            yr -= c.domainsize.y *  ::floor( 0.5f + yr / c.domainsize.y );
            zr -= c.domainsize.z *  ::floor( 0.5f + zr / c.domainsize.z );

            const float rij2 = xr * xr + yr * yr + zr * zr;
            const float invrij = rsqrtf( rij2 );
            const float rij = rij2 * invrij;
            const float wr = max( ( float )0, 1 - rij * c.invrc );

            const bool collision =  rij2 < 1;

            if( collision )
                fc += wr;// printf("ref p %d colliding with %d\n", i, j);

            cnt += collision;
        }
        printf( "i found %d host interactions and with cuda i found %d\n", cnt, ( int )axayaz[0 + 3 * ii] );
        assert( cnt == ( float )axayaz[0 + 3 * ii] );
        printf( "fc aij ref %f vs cuda %e\n", fc, ( float )axayaz[1 + 3 * ii] );
        assert( fabs( fc - ( float )axayaz[1 + 3 * ii] ) < 1e-4 );
    }

    printf( "test done.\n" );
    sleep( 1 );
    exit( 0 );
#endif
}


int * fdpd_order = NULL;
float * fdpd_pv = NULL, *fdpd_a = NULL;

void forces_dpd_cuda( const float * const xp, const float * const yp, const float * const zp,
                      const float * const xv, const float * const yv, const float * const zv,
                      float * const xa, float * const ya, float * const za,
                      const int np,
                      const float rc,
                      const float LX, const float LY, const float LZ,
                      const float aij,
                      const float gamma,
                      const float sigma,
                      const float invsqrtdt,
                      const float seed )
{
    if( np <= 0 ) return;

    printf("%s %d\n",__FILE__,__LINE__);

    if( np > fdpd_oldnp ) {
        if( fdpd_oldnp > 0 ) {
            CUDA_CHECK( cudaFreeHost( fdpd_pv ) );
            CUDA_CHECK( cudaFreeHost( fdpd_order ) );
            CUDA_CHECK( cudaFreeHost( fdpd_a ) );
        }

        CUDA_CHECK( cudaHostAlloc( &fdpd_pv, sizeof( float ) * np * 6, cudaHostAllocDefault ) );
        CUDA_CHECK( cudaHostAlloc( &fdpd_order, sizeof( int ) * np, cudaHostAllocDefault ) );
        CUDA_CHECK( cudaHostAlloc( &fdpd_a, sizeof( float ) * np * 3, cudaHostAllocDefault ) );

        //this will be done by forces_dpd_cuda
        //fdpd_oldnp = np;
    }

    for( int i = 0; i < np; ++i ) {
        fdpd_pv[0 + 6 * i] = xp[i];
        fdpd_pv[1 + 6 * i] = yp[i];
        fdpd_pv[2 + 6 * i] = zp[i];
        fdpd_pv[3 + 6 * i] = xv[i];
        fdpd_pv[4 + 6 * i] = yv[i];
        fdpd_pv[5 + 6 * i] = zv[i];
    }

    forces_dpd_cuda_aos( fdpd_pv, fdpd_a, fdpd_order, np, rc, LX, LY, LZ,
                         aij, gamma, sigma, invsqrtdt, seed, false );

    //delete [] pv;

    for( int i = 0; i < np; ++i ) {
        xa[fdpd_order[i]] += fdpd_a[0 + 3 * i];
        ya[fdpd_order[i]] += fdpd_a[1 + 3 * i];
        za[fdpd_order[i]] += fdpd_a[2 + 3 * i];
    }

    //delete [] a;

    //delete [] order;
}
