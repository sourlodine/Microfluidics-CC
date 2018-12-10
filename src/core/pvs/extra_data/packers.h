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
    ParticlePacker(ParticleVector* pv, LocalParticleVector* lpv, cudaStream_t stream)
    {
        if (pv == nullptr || lpv == nullptr) return;

        auto& manager = lpv->extraPerParticle;

        int n = 0;
        bool upload = false;

        auto registerChannel = [&] (int sz, char* ptr, int typesize) {

            if (manager.channelPtrs.size() <= n)
            {
                manager.channelPtrs.        resize(n+1, stream);
                manager.channelSizes.       resize(n+1, stream);
                manager.channelShiftTypes.  resize(n+1, stream);

                upload = true;
            }

            if (ptr != manager.channelPtrs[n]) upload = true;

            manager.channelSizes[n] = sz;
            manager.channelPtrs[n] = ptr;
            manager.channelShiftTypes[n] = typesize;

            packedSize_byte += sz;
            n++;
        };

        registerChannel(
                sizeof(Particle),
                reinterpret_cast<char*>(lpv->coosvels.devPtr()),
                sizeof(float) );


        for (const auto& name_desc : manager.getSortedChannels())
        {
            auto desc = name_desc.second;

            if (desc->needExchange)
            {
                int sz = desc->container->datatype_size();

                if (sz % sizeof(int) != 0)
                    die("Size of extra data per particle should be divisible by 4 bytes (PV '%s', data entry '%s')",
                        pv->name.c_str(), name_desc.first.c_str());

                if ( sz % sizeof(float4) && (desc->shiftTypeSize == 4 || desc->shiftTypeSize == 8) )
                    die("Size of extra data per particle should be divisible by 16 bytes"
                        "when shifting is required (PV '%s', data entry '%s')",
                        pv->name.c_str(), name_desc.first.c_str());

                registerChannel(
                        sz,
                        reinterpret_cast<char*>(desc->container->genericDevPtr()),
                        desc->shiftTypeSize);
            }
        }

        nChannels = n;
        packedSize_byte = ( (packedSize_byte + sizeof(float4) - 1) / sizeof(float4) ) * sizeof(float4);

        if (upload)
        {
            manager.channelPtrs.        uploadToDevice(stream);
            manager.channelSizes.       uploadToDevice(stream);
            manager.channelShiftTypes.  uploadToDevice(stream);
        }

        channelData         = manager.channelPtrs.        devPtr();
        channelSizes        = manager.channelSizes.       devPtr();
        channelShiftTypes   = manager.channelShiftTypes.  devPtr();
    }
};


/**
 * Class that uses DevicePacker to pack extra data per object
 */
struct ObjectExtraPacker : public DevicePacker
{
    ObjectExtraPacker(ObjectVector* ov, LocalObjectVector* lov, cudaStream_t stream)
    {
        if (ov == nullptr || lov == nullptr) return;

        auto& manager = lov->extraPerObject;

        int n = 0;
        bool upload = false;

        auto registerChannel = [&] (int sz, char* ptr, int typesize) {

            if (manager.channelPtrs.size() <= n)
            {
                manager.channelPtrs.        resize(n+1, stream);
                manager.channelSizes.       resize(n+1, stream);
                manager.channelShiftTypes.  resize(n+1, stream);

                upload = true;
            }

            if (ptr != manager.channelPtrs[n]) upload = true;

            manager.channelSizes[n] = sz;
            manager.channelPtrs[n] = ptr;
            manager.channelShiftTypes[n] = typesize;

            packedSize_byte += sz;
            n++;
        };

        for (const auto& name_desc : manager.getSortedChannels())
        {
            auto desc = name_desc.second;

            if (desc->needExchange)
            {
                int sz = desc->container->datatype_size();

                if (sz % sizeof(int) != 0)
                    die("Size of extra data per particle should be divisible by 4 bytes (PV '%s', data entry '%s')",
                        ov->name.c_str(), name_desc.first.c_str());

                if ( sz % sizeof(float4) && (desc->shiftTypeSize == 4 || desc->shiftTypeSize == 8) )
                    die("Size of extra data per particle should be divisible by 16 bytes"
                        "when shifting is required (PV '%s', data entry '%s')",
                        ov->name.c_str(), name_desc.first.c_str());

                registerChannel(
                        sz,
                        reinterpret_cast<char*>(desc->container->genericDevPtr()),
                        desc->shiftTypeSize);
            }
        }

        nChannels = n;
        packedSize_byte = ( (packedSize_byte + sizeof(float4) - 1) / sizeof(float4) ) * sizeof(float4);

        if (upload)
        {
            manager.channelPtrs.        uploadToDevice(stream);
            manager.channelSizes.       uploadToDevice(stream);
            manager.channelShiftTypes.  uploadToDevice(stream);
        }

        channelData         = manager.channelPtrs.        devPtr();
        channelSizes        = manager.channelSizes.       devPtr();
        channelShiftTypes   = manager.channelShiftTypes.  devPtr();
    }
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

    ObjectPacker(ObjectVector* ov = nullptr, LocalObjectVector* lov = nullptr, cudaStream_t stream = 0) :
        part(ov, lov, stream), obj(ov, lov, stream)
    {
        if (ov == nullptr || lov == nullptr) return;
        totalPackedSize_byte = part.packedSize_byte * ov->objSize + obj.packedSize_byte;
    }
};

