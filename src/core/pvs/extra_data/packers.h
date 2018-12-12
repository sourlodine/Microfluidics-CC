#pragma once

#include <cassert>
#include <core/pvs/particle_vector.h>
#include <core/pvs/object_vector.h>

/**
 * Class that packs nChannels of arbitrary data into a chunk of contiguous memory
 * or unpacks it in the same manner
 */
struct DevicePacker
{
    int packedSize_byte = 0;

    int nChannels = 0;                    ///< number of data channels to pack / unpack
    int* channelSizes        = nullptr;   ///< size if bytes of each channel entry, e.g. sizeof(Particle)
    int* channelShiftTypes   = nullptr;   ///< if type is 4, then treat data to shift as float3, if it is 8 -- as double3
    char** channelData       = nullptr;   ///< device pointers of the packed data

    /**
     * Pack entity with id srcId into memory starting with dstAddr
     * Don't apply no shifts
     */
    inline __device__ void pack(int srcId, char* dstAddr) const
    {
        _packShift<ShiftMode::NoShift> (srcId, dstAddr, make_float3(0));
    }

    /**
     * Pack entity with id srcId into memory starting with dstAddr
     * Apply shifts where needed
     */
    inline __device__ void packShift(int srcId, char* dstAddr, float3 shift) const
    {
        _packShift<ShiftMode::NeedShift>  (srcId, dstAddr, shift);
    }

    /**
     * Unpack entity from memory by srcAddr to the channels to id dstId
     */
    inline __device__ void unpack(const char* srcAddr, int dstId) const
    {
        for (int i = 0; i < nChannels; i++)
        {
            copy(channelData[i] + channelSizes[i]*dstId, srcAddr, channelSizes[i]);
            srcAddr += channelSizes[i];
        }
    }

private:

    enum class ShiftMode
    {
        NeedShift, NoShift
    };

    /**
     * Copy nchunks*sizeof(T) bytes \c from from to \c to
     */
    template<typename T>
    inline __device__ void _copy(char* to, const char* from, int nchunks) const
    {
        auto _to   = (T*)to;
        auto _from = (const T*)from;

#pragma unroll 2
        for (int i=0; i<nchunks; i++)
            _to[i] = _from[i];
    }

    /**
     * Copy size_bytes bytes from from to to
     * Speed up copying by choosing the widest possible data type
     * and calling the appropriate _copy function
     */
    inline __device__ void copy(char* to, const char* from, int size_bytes) const
    {
        assert(size_bytes % 4 == 0);

        if (size_bytes % 16 == 0)
            _copy<int4>(to, from, size_bytes / 16);
        else if (size_bytes % 8 == 0)
            _copy<int2>(to, from, size_bytes / 8);
        else
            _copy<int> (to, from, size_bytes / 4);
    }

    /**
     * Packing implementation
     * Template parameter NEEDSHIFT governs shifting
     */
    template <ShiftMode shiftmode>
    inline __device__ void _packShift(int srcId, char* dstAddr, float3 shift) const
    {
        for (int i = 0; i < nChannels; i++)
        {
            const int size = channelSizes[i];
            int done = 0;

            if (shiftmode == ShiftMode::NeedShift)
            {
                if (channelShiftTypes[i] == sizeof(float))
                {
                    float4 val = *((float4*) ( channelData[i] + size*srcId ));
                    val.x += shift.x;
                    val.y += shift.y;
                    val.z += shift.z;
                    *((float4*) dstAddr) = val;

                    done = sizeof(float4);
                }
                else if (channelShiftTypes[i] == sizeof(double))
                {
                    double4 val = *((double4*) ( channelData[i] + size*srcId ));
                    val.x += shift.x;
                    val.y += shift.y;
                    val.z += shift.z;
                    *((double4*) dstAddr) = val;

                    done = sizeof(double4);
                }
            }

            copy(dstAddr + done, channelData[i] + size*srcId + done, size - done);
            dstAddr += size;
        }
    }
};


/**
 * Class that uses DevicePacker to pack a single particle entity
 */
struct ParticlePacker : public DevicePacker
{
    ParticlePacker(ParticleVector* pv, LocalParticleVector* lpv, cudaStream_t stream);
};


/**
 * Class that uses DevicePacker to pack extra data per object
 */
struct ObjectExtraPacker : public DevicePacker
{
    ObjectExtraPacker(ObjectVector* ov, LocalObjectVector* lov, cudaStream_t stream);
};


/**
 * Class that uses both ParticlePacker and ObjectExtraPacker
 * to pack everything. Provides totalPackedSize_byte of an object
 */
struct ObjectPacker
{
    ParticlePacker    part;
    ObjectExtraPacker obj;
    int totalPackedSize_byte = 0;

    ObjectPacker(ObjectVector* ov = nullptr, LocalObjectVector* lov = nullptr, cudaStream_t stream = 0);
};

