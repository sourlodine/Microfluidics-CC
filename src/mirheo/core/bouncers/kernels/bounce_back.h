#pragma once

#include <core/utils/cpu_gpu_defines.h>
#include <core/utils/macros.h>

#include <random>

class BounceBack
{
public:
    BounceBack() = default;

    void update(__UNUSED std::mt19937& rng) {}

#ifdef __NVCC__
    __device__  real3 newVelocity(real3 uOld, real3 uWall, __UNUSED real3 n, __UNUSED real mass) const
    {
        return uWall - (uOld - uWall);
    }
#endif
};
