#pragma once

#include <core/domain.h>
#include <core/utils/cpu_gpu_defines.h>
#include <core/utils/type_map.h>

namespace TypeShift
{
template <typename T>
__HD__ inline void add(T& v, float3 s)
{
    v.x += s.x;
    v.y += s.y;
    v.z += s.z;
}

template <typename T>
__HD__ inline void shift(T& var, float3 shift) {}

__HD__ inline void shift(float3&      var, float3 shift) {add(var,   shift);}
__HD__ inline void shift(float4&      var, float3 shift) {add(var,   shift);}
__HD__ inline void shift(double3&     var, float3 shift) {add(var,   shift);}
__HD__ inline void shift(double4&     var, float3 shift) {add(var,   shift);}
__HD__ inline void shift(RigidMotion& var, float3 shift) {add(var.r, shift);}

__HD__ inline void shift(COMandExtent& var, float3 shift)
{
    add(var.com,  shift);
    add(var.low,  shift);
    add(var.high, shift);
}

} // namespace TypeShift
