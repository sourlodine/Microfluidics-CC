#include "vv.h"

#include <core/utils/kernel_launch.h>
#include <core/logger.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/views/pv.h>

#include "integration_kernel.h"

#include "forcing_terms/none.h"
#include "forcing_terms/const_dp.h"
#include "forcing_terms/periodic_poiseuille.h"


template<class ForcingTerm>
IntegratorVV<ForcingTerm>::IntegratorVV(const YmrState *state, std::string name, ForcingTerm forcingTerm) :
    Integrator(state, name), forcingTerm(forcingTerm)
{}

template<class ForcingTerm>
IntegratorVV<ForcingTerm>::~IntegratorVV() = default;


template<class ForcingTerm>
void IntegratorVV<ForcingTerm>::stage1(ParticleVector *pv, cudaStream_t stream)
{}

/**
 * The new coordinates and velocities of a particle will be computed
 * as follows:
 * \f$
 * \begin{cases}
 *  f'_p = ForcingTerm(f_p, x_p, v_p) \\
 *  v_{new} = v_p + \dfrac{f'_p}{m_p}  \delta t \\
 *  x_{new} = x_p + v_{new} \, \delta t
 * \end{cases}
 * \f$
 *
 * @tparam ForcingTerm is a functor that can modify computed force
 * per particles (typically add some force field). It has to
 * provide two functions:
 * - This function will be called once before integration and
 *   allows the functor to obtain required variables or data
 *   channels from the ParticleVector:
 *   \code setup(ParticleVector* pv, float t) \endcode
 *
 * - This should be a \c \_\_device\_\_ operator that modifies
 *   the force. It will be called for each particle during the
 *   integration:
 *   \code float3 operator()(float3 f0, Particle p) const \endcode
 *
 */
template<class ForcingTerm>
void IntegratorVV<ForcingTerm>::stage2(ParticleVector *pv, cudaStream_t stream)
{
    float t = state->currentTime;
    float dt = state->dt;
    static_assert(std::is_same<decltype(forcingTerm.setup(pv, t)), void>::value,
            "Forcing term functor must provide member"
            "void setup(ParticleVector*, float)");

    auto& _fterm = forcingTerm;
    _fterm.setup(pv, t);

    auto st2 = [_fterm] __device__ (Particle& p, const float3 f, const float invm, const float dt) {

        float3 modF = _fterm(f, p);

        p.u += modF*invm*dt;
        p.r += p.u*dt;
    };

    int nthreads = 128;
    debug2("Integrating (stage 2) %d %s particles, timestep is %f", pv->local()->size(), pv->name.c_str(), dt);

    // New particles now become old
    std::swap(pv->local()->coosvels, *pv->local()->extraPerParticle.getData<Particle>(ChannelNames::oldParts));
    PVviewWithOldParticles pvView(pv, pv->local());

    // Integrate from old to new
    SAFE_KERNEL_LAUNCH(
            integrationKernel,
            getNblocks(2*pvView.size, nthreads), nthreads, 0, stream,
            pvView, dt, st2 );

    // PV may have changed, invalidate all
    pv->haloValid = false;
    pv->redistValid = false;
    pv->cellListStamp++;
}

template class IntegratorVV<Forcing_None>;
template class IntegratorVV<Forcing_ConstDP>;
template class IntegratorVV<Forcing_PeriodicPoiseuille>;
