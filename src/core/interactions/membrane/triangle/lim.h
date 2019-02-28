#pragma once

#include "common.h"
#include "../parameters.h"

#include <core/utils/cpu_gpu_defines.h>
#include <core/utils/helper_math.h>
#include <core/mesh/membrane.h>

#include <cmath>

template <StressFreeState stressFreeState>
class TriangleLimForce
{
public:    
    struct LengthsArea
    {
        real l0;   // first  eq edge length
        real l1;   // second eq edge length
        real a;    // eq triangle area
        real dotp; // dot product of 2 above edges
    };

    using EquilibriumTriangleDesc = LengthsArea;
    using ParametersType          = LimParameters;
    
    TriangleLimForce(ParametersType p, const Mesh *mesh, real lscale) :
        lscale(lscale)
    {
        a3 = p.a3;
        a4 = p.a4;
        b1 = p.b1;
        b2 = p.b2;

        ka = p.ka * lscale * lscale;
        mu = p.mu * lscale * lscale;
        
        area0   = p.totArea0 * lscale * lscale / mesh->getNtriangles();
        length0 = sqrt(area0 * 4.0 / sqrt(3.0));
    }

    __D__ inline EquilibriumTriangleDesc getEquilibriumDesc(const MembraneMeshView& mesh, int i0, int i1) const
    {
        EquilibriumTriangleDesc eq;
        if (stressFreeState == StressFreeState::Active)
        {
            eq.l0   = mesh.initialLengths    [i0] * lscale;
            eq.l1   = mesh.initialLengths    [i1] * lscale;
            eq.a    = mesh.initialAreas      [i0] * lscale * lscale;
            eq.dotp = mesh.initialDotProducts[i0] * lscale * lscale;
        }
        else
        {
            eq.l0   = this->length0;
            eq.l1   = this->length0;
            eq.a    = this->area0;
            eq.dotp = this->length0 * 0.5_r;
        }
        return eq;
    }

    __D__ inline real safeSqrt(real a) const
    {
        return a > 0.0_r ? sqrt(a) : 0.0_r;
    }
    
    __D__ inline real3 operator()(real3 v1, real3 v2, real3 v3, EquilibriumTriangleDesc eq) const
    {
        real3 x12 = v2 - v1;
        real3 x13 = v3 - v1;
        real3 x32 = v2 - v3;

        real3 normalArea2 = cross(x12, x13);
        real area = 0.5_r * length(normalArea2);
        real area_inv = 1.0_r / area;
        real area0_inv = 1.0_r / eq.a;

        real3 derArea  = (0.25_r * area_inv) * cross(normalArea2, x32);

        real alpha = area * area0_inv - 1;
        real coeffAlpha = 0.5_r * ka * alpha * (2 + alpha * (3 * a3 + alpha * 4 * a4));

        real3 fArea = coeffAlpha * derArea;
        
        real e0sq_A = dot(x12, x12) * area_inv;
        real e1sq_A = dot(x13, x13) * area_inv;

        real e0sq_A0 = eq.l0*eq.l0 * area0_inv;
        real e1sq_A0 = eq.l1*eq.l1 * area0_inv;

        real dotp = dot(x12, x13);
        real sign = (dotp * eq.dotp) >= 0.0_r ? 1.0_r : -1.0_r;
        
        real beta = 0.125_r * (e0sq_A0*e1sq_A + e1sq_A0*e0sq_A
                               - 2._r * sign * safeSqrt((e0sq_A0 * e1sq_A0 - 4._r) * (e0sq_A * e1sq_A - 4._r))
                               - 8._r);

        real dsqrt = safeSqrt((e0sq_A0*e1sq_A0-4) / (e0sq_A*e1sq_A-4));
            
        real derBeta0 = 0.125_r * (e1sq_A0 - sign * dsqrt * e1sq_A);
        real derBeta1 = 0.125_r * (e0sq_A0 - sign * dsqrt * e0sq_A);

        real3 der_e0sq_A = 2 * area_inv * x12 - e0sq_A * area_inv * derArea;
        real3 der_e1sq_A = 2 * area_inv * x13 - e1sq_A * area_inv * derArea;
        
        real3 derBeta  = derBeta0 * der_e0sq_A + derBeta1 * der_e1sq_A;
        real3 derAlpha = area0_inv * derArea;
            
        real coefAlpha = eq.a * mu * b1 * beta;
        real coefBeta  = eq.a * mu * (2*b2*beta + alpha * b1 + 1);

        real3 fShear = coefAlpha * derAlpha + coefBeta * derBeta;

        return fArea + fShear;
    }
        
private:
    
    real ka, mu;
    real a3, a4, b1, b2;

    real length0, area0; ///< only useful when StressFree is false
    real lscale;
};
