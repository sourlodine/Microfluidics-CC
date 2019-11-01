#pragma once

#include <mirheo/core/utils/cpu_gpu_defines.h>
#include <mirheo/core/utils/cuda_rng.h>
#include <mirheo/core/utils/macros.h>
#include <mirheo/core/utils/helper_math.h>

#include <random>

// reflection with random scattering
// according to Maxwell distr
class BounceMaxwell
{
public:
    BounceMaxwell(real kBT) :
        kBT(kBT)
    {}

    void update(std::mt19937& rng)
    {
        std::uniform_real_distribution<real> dis(0._r, 1._r);
        seed1 = dis(rng);
        seed2 = dis(rng);
    }

#ifdef __NVCC__
    __device__ real3 newVelocity(__UNUSED real3 uOld, real3 uWall, real3 n, real mass) const
    {
        constexpr int maxTries = 50;
        const real2 rand1 = Saru::normal2(seed1, threadIdx.x, blockIdx.x);
        const real2 rand2 = Saru::normal2(seed2, threadIdx.x, blockIdx.x);

        real3 v = make_real3(rand1.x, rand1.y, rand2.x);

        for (int i = 0; i < maxTries; ++i)
        {
            if (dot(v, n) > 0) break;

            const real2 rand3 = Saru::normal2(rand2.y, threadIdx.x, blockIdx.x);
            const real2 rand4 = Saru::normal2(rand3.y, threadIdx.x, blockIdx.x);
            v = make_real3(rand3.x, rand3.y, rand4.x);
        }
        v = normalize(v) * math::sqrt(kBT / mass);

        return uWall + v;
    }
#endif

private:

    real seed1{0._r};
    real seed2{0._r};
    real kBT;
};
