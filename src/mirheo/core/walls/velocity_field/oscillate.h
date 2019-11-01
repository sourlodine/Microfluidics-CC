#pragma once

#include <mirheo/core/domain.h>
#include <mirheo/core/datatypes.h>

#include <mirheo/core/utils/cpu_gpu_defines.h>
#include <mirheo/core/utils/helper_math.h>

namespace mirheo
{

class ParticleVector;

class VelocityField_Oscillate
{
public:
    VelocityField_Oscillate(real3 vel, real period) :
        vel(vel), period(period)
    {
        if (period <= 0)
            die("Oscillating period should be strictly positive");
    }

    void setup(real t, __UNUSED DomainInfo domain)
    {
        cosOmega = math::cos(2*M_PI * t / period);
    }

    const VelocityField_Oscillate& handler() const { return *this; }

    __D__ inline real3 operator()(__UNUSED real3 coo) const
    {
        return vel * cosOmega;
    }

private:
    real3 vel;
    real period;

    real cosOmega;

    DomainInfo domain;
};

} // namespace mirheo
