#pragma once

#include <cmath>

class SimpleMDPDDensityKernel
{
public:
    static constexpr real normalization = 15.0 / (2.0 * M_PI);

    __D__ inline real operator()(real r, real invrc) const
    {
        const real rm = (1.f - r * invrc) * invrc;

        return normalization * rm * rm * invrc;
    }
};

class WendlandC2DensityKernel
{
public:
    static constexpr real normalization = 21.0 / (2.0 * M_PI);

    __D__ inline real operator()(real r, real invrc) const
    {
        const real r_ = r * invrc;
        const real rm = 1.0f - r_;
        const real rm2 = rm * rm;
        const real invrc3 = invrc * invrc * invrc;
        
        return normalization * invrc3 * rm2 * rm2 * (1.0f + 4.0f * r_);
    }

    __D__ inline real derivative(real r, real invrc) const
    {
        const real r_ = r * invrc;
        const real rm = r_ - 1.f;
        const real invrc3 = invrc * invrc * invrc;
        return 20.0f * invrc3 * normalization * r_ * rm*rm*rm * invrc;
    }
};

