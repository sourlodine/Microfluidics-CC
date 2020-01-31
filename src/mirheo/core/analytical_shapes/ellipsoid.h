#pragma once

#include <mirheo/core/utils/cpu_gpu_defines.h>
#include <mirheo/core/utils/cuda_common.h>
#include <mirheo/core/utils/helper_math.h>

namespace mirheo
{

class Ellipsoid
{
public:
    Ellipsoid(real3 axes) :
        axes_(axes),
        invAxes_(1.0 / axes)
    {}

    __HD__ inline real inOutFunction(real3 r) const
    {
        return sqr(r.x * invAxes_.x) + sqr(r.y * invAxes_.y) + sqr(r.z * invAxes_.z) - 1.0_r;
    }

    __HD__ inline real3 normal(real3 r) const
    {
        constexpr real eps {1e-6_r};
        const real3 n {axes_.y*axes_.y * axes_.z*axes_.z * r.x,
                       axes_.z*axes_.z * axes_.x*axes_.x * r.y,
                       axes_.x*axes_.x * axes_.y*axes_.y * r.z};
        const real l = length(n);

        if (l > eps)
            return n / l;

        return {1.0_r, 0.0_r, 0.0_r}; // arbitrary if r = 0
    }
    
    inline real3 inertiaTensor(real totalMass) const
    {
        return totalMass / 5.0_r * make_real3
            (sqr(axes_.y) + sqr(axes_.z),
             sqr(axes_.x) + sqr(axes_.z),
             sqr(axes_.x) + sqr(axes_.y));
    }

    static const char *desc;
    
private:    
    real3 axes_, invAxes_;
};

} // namespace mirheo
