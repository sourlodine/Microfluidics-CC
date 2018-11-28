#pragma once

#include <core/utils/cuda_common.h>
#include <core/utils/cuda_rng.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/views/ov.h>
#include <core/mesh.h>

template <typename View>
__device__ inline float3 fetchVertex(View view, int i)
{
    // 2 because of float4
    return Float3_int(view.particles[2 * i]).v;
}

__device__ inline float triangleArea(float3 v0, float3 v1, float3 v2)
{
    return 0.5f * length(cross(v1 - v0, v2 - v0));
}

__device__ inline float triangleSignedVolume(float3 v0, float3 v1, float3 v2)
{
    return 0.1666666667f *
        (- v0.z*v1.y*v2.x + v0.z*v1.x*v2.y + v0.y*v1.z*v2.x
         - v0.x*v1.z*v2.y - v0.y*v1.x*v2.z + v0.x*v1.y*v2.z);
}
